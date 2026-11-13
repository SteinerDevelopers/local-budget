// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// E5 §3/§4/§6 — the four Data tiles and the QuickAdd rate stamp, exercised
// end to end through the widget tree with the [Io] seam faked. File pickers
// and share sheets do not exist in tests; everything above the byte
// boundary here is the real production code path (E5 §8).
//
// Same drift rules as manage_test.dart: db.close() inside the test body.
// Backup/restore run wal_checkpoint(TRUNCATE) (E5 §7), so those tests get a
// FILE-backed db in a temp dir, exactly like a device; kdfIterations: 1000
// keeps the KDF honest but instant (§8 seam).
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/capture_services.dart';
import 'package:local_budget/features/manage/io.dart';
import 'package:local_budget/features/manage/manage_screen.dart';
import 'package:local_budget/main.dart';
import 'package:local_budget/version.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class FakeIo implements Io {
  FakeIo([this.pickResult]);

  PickedFile? pickResult;
  final shared = <(Uint8List bytes, String name)>[];
  final saved = <(Uint8List bytes, String name, String? title)>[];
  bool cancelSave = false;
  Object? saveThrows;

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async => pickResult;

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
  }) async => shared.add((bytes, fileName));

  @override
  Future<Uri?> saveFile({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
  }) async {
    if (saveThrows != null) throw saveThrows!;
    saved.add((bytes, fileName, dialogTitle));
    return cancelSave ? null : Uri.parse('content://fake/saved/$fileName');
  }
}

/// E11 document-import seam: the intake hands back opaque bytes the
/// [TextExtractor] fake maps to canned lines (tag = first byte lets one
/// extractor answer per-page for scanned PDFs). Nothing below this boundary
/// is faked — routing, parsing, preview and commit are the real path.
class DocIntake implements CaptureIntake {
  @override
  bool allowScanner = true;
  @override
  bool get hasScreenshotRow => false;

  @override
  Future<CapturePick?> pick(CaptureChoice choice) async =>
      CapturePick(bytes: Uint8List.fromList([0]), choice: choice);
}

class LinesExtractor implements TextExtractor {
  LinesExtractor({this.lines = const [], this.byTag = const {}});
  final List<String> lines;
  final Map<int, List<String>> byTag;

  @override
  Future<List<String>> extractText(Uint8List image) async =>
      byTag[image.isEmpty ? 0 : image.first] ?? lines;
}

class FakeScannedPages {
  FakeScannedPages(this.count);
  final int count;

  Future<List<Uint8List>> renderPages(Uint8List pdf) => Future.value([
    for (var i = 1; i <= count; i++) Uint8List.fromList([i]),
  ]);
}

CaptureServices docServices({
  List<String> lines = const [],
  Map<int, List<String>> byTag = const {},
  int scannedPages = 0,
}) => CaptureServices(
  intake: DocIntake(),
  extractor: LinesExtractor(lines: lines, byTag: byTag),
  scannedPdfPages: scannedPages == 0
      ? null
      : FakeScannedPages(scannedPages).renderPages,
);

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final now = DateTime.now();
  final today = FxService.dayKey(now);

  /// A file-backed db + docs dir like a device (backup wants real WAL).
  Future<({AppDatabase db, Directory docs, LedgerRepository repo})>
  liveDb() async {
    final docs = Directory.systemTemp.createTempSync('lzb_flows');
    final db = AppDatabase.openFile('${docs.path}/localbudget.sqlite');
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await repo.setSetting('scannerConsent', 'fast'); // #56 gate: seeded answer
    return (db: db, docs: docs, repo: repo);
  }

  Future<void> tearDownDb(
    ({AppDatabase db, Directory docs, LedgerRepository repo}) r,
  ) async {
    await r.db.close();
    r.docs.deleteSync(recursive: true);
  }

  Future<void> pumpManage(
    WidgetTester tester, {
    required LedgerRepository repo,
    AppDatabase? db,
    Directory? docs,
    Io? io,
    CaptureServices? capture,
    FxService? fx,
    bool liveFxVisible = false,
    Future<void> Function(Backup backup)? restore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManageScreen(
          repository: repo,
          db: db,
          docsDir: docs,
          io: io ?? FakeIo(),
          capture: capture,
          fx: fx,
          liveFxVisible: liveFxVisible,
          restore: restore,
          kdfIterations: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The pro flavor carries extra paid-pack rows; the lower settings rows
  /// can fall below the 800x600 viewport — and out of the ListView cache
  /// extent, where they are not even built — so reveal before touching.
  Future<void> revealRow(WidgetTester tester, String key) async {
    final row = find.byKey(Key(key));
    if (row.evaluate().isEmpty) {
      // Positive delta reveals rows below the fold (scrollUntilVisible
      // negates it into a finger swipe).
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String key) async {
    await revealRow(tester, key);
    await tester.tap(find.byKey(Key(key)));
  }

  Future<void> enterPassphrase(
    WidgetTester tester,
    String phrase, {
    bool withConfirm = false,
  }) async {
    await tester.enterText(find.byKey(const Key('passphrase-field')), phrase);
    if (withConfirm) {
      await tester.enterText(
        find.byKey(const Key('passphrase-confirm-field')),
        phrase,
      );
    }
    await tester.tap(find.byKey(const Key('passphrase-next')));
    await tester.pumpAndSettle();
  }

  /// Snackbars run on a 4 s timer — expire them so no timer outlives the
  /// fake-async zone (drift rule #2).
  Future<void> expireSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('export CSV (§3)', () {
    testWidgets('All accounts shares a spreadsheet copy of the ledger', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo();
      try {
        final cash = await r.repo.defaultAccount();
        await r.repo.addTransaction(
          accountId: cash.id,
          date: DateTime(2026, 11, 1),
          amount: Money(475, Currency.resolve('USD')),
          merchant: 'Coffee Shop',
          source: TransactionSource.manual,
        );
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);

        await tapRow(tester, 'export-csv');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('export-account-all')), findsOneWidget);
        await tester.tap(find.byKey(const Key('export-account-all')));
        await tester.pumpAndSettle();

        expect(io.shared, hasLength(1));
        final (bytes, name) = io.shared.single;
        expect(name, matches(r'^budget-export-\d{4}-\d{2}-\d{2}\.csv$'));
        final text = utf8.decode(bytes);
        expect(
          text,
          startsWith('date,description,category,note,amount,currency,account'),
        );
        expect(text, contains('Coffee Shop'));
        expect(find.text('Export ready to share as $name'), findsOneWidget);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('one account exports only its own rows', (tester) async {
      final r = await liveDb();
      final io = FakeIo();
      try {
        final cash = await r.repo.defaultAccount();
        final giroId = await r.repo.createAccount(
          name: 'Giro',
          currencyCode: 'USD',
        );
        await r.repo.addTransaction(
          accountId: cash.id,
          date: DateTime(2026, 11, 1),
          amount: Money(475, Currency.resolve('USD')),
          merchant: 'Cash Only',
          source: TransactionSource.manual,
        );
        await r.repo.addTransaction(
          accountId: giroId,
          date: DateTime(2026, 11, 2),
          amount: Money(900, Currency.resolve('USD')),
          merchant: 'Giro Only',
          source: TransactionSource.manual,
        );
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);

        await tapRow(tester, 'export-csv');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('export-account-$giroId')));
        await tester.pumpAndSettle();

        final text = utf8.decode(io.shared.single.$1);
        expect(text, contains('Giro Only'));
        expect(text, isNot(contains('Cash Only')));
      } finally {
        await tearDownDb(r);
      }
    });
  });

  group('back up now (§7)', () {
    testWidgets(
      'passphrase twice, then an LZBK1 file to the user’s save target',
      (tester) async {
        final r = await liveDb();
        final io = FakeIo();
        try {
          await pumpManage(
            tester,
            repo: r.repo,
            db: r.db,
            docs: r.docs,
            io: io,
          );

          await tapRow(tester, 'back-up');
          await tester.pumpAndSettle();
          expect(
            find.text('Choose a passphrase for this backup'),
            findsOneWidget,
          );
          await enterPassphrase(
            tester,
            'right horse battery',
            withConfirm: true,
          );

          // #50/C4: the bytes go to the OS save dialog the user commands —
          // never silently to a cache behind a share sheet.
          expect(io.saved, hasLength(1));
          final (bytes, name, title) = io.saved.single;
          expect(title, 'Save your backup');
          expect(name, matches(r'^localbudget-backup-\d{4}-\d{2}-\d{2}\.lzb$'));
          expect(utf8.decode(bytes.sublist(0, 5)), 'LZBK1');
          expect(io.shared, isEmpty);
          expect(
            find.textContaining('Saved $name to the location you picked'),
            findsOneWidget,
          );
        } finally {
          await tearDownDb(r);
        }
      },
    );

    testWidgets('a cancelled save dialog says nothing was saved', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo()..cancelSave = true;
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);

        await tapRow(tester, 'back-up');
        await tester.pumpAndSettle();
        await enterPassphrase(tester, 'right horse battery', withConfirm: true);

        expect(io.shared, isEmpty);
        expect(
          find.text('Backup cancelled — nothing was saved.'),
          findsOneWidget,
        );
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('a save that throws says it failed — never silent success', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo()..saveThrows = StateError('storage gone');
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);

        await tapRow(tester, 'back-up');
        await tester.pumpAndSettle();
        await enterPassphrase(tester, 'right horse battery', withConfirm: true);

        expect(io.saved, isEmpty);
        expect(find.textContaining('That did not work'), findsOneWidget);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('empty and mismatched passphrases are refused inline', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo();
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);
        await tapRow(tester, 'back-up');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('passphrase-next')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'A backup without a passphrase is just a file anyone can open.',
          ),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('passphrase-field')),
          'one thing',
        );
        await tester.enterText(
          find.byKey(const Key('passphrase-confirm-field')),
          'another',
        );
        await tester.tap(find.byKey(const Key('passphrase-next')));
        await tester.pumpAndSettle();
        expect(find.text('The two entries do not match.'), findsOneWidget);
        expect(io.shared, isEmpty);
      } finally {
        await tearDownDb(r);
      }
    });
  });

  group('restore from backup (§1 — the one destructive path)', () {
    testWidgets('confirm dialog names both replaced stores, then restore', (
      tester,
    ) async {
      final r = await liveDb();
      final bytes = await createBackup(
        db: r.db,
        attachments: AttachmentStore(r.docs),
        passphrase: 'open sesame',
        appVersion: appVersion,
        kdfIterations: 1000,
      );
      final io = FakeIo(PickedFile('trip.lzb', bytes));
      Backup? restored;
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          io: io,
          restore: (b) async => restored = b,
        );

        await tapRow(tester, 'restore');
        await tester.pumpAndSettle();
        await enterPassphrase(tester, 'open sesame');

        expect(find.byKey(const Key('restore-confirm')), findsOneWidget);
        expect(
          find.textContaining('ledger and all attachment images'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('restore-go')));
        await tester.pumpAndSettle();
        expect(restored, isNotNull);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('Cancel leaves everything alone', (tester) async {
      final r = await liveDb();
      final bytes = await createBackup(
        db: r.db,
        attachments: AttachmentStore(r.docs),
        passphrase: 'open sesame',
        appVersion: appVersion,
        kdfIterations: 1000,
      );
      final io = FakeIo(PickedFile('trip.lzb', bytes));
      var called = false;
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          io: io,
          restore: (_) async => called = true,
        );
        await tapRow(tester, 'restore');
        await tester.pumpAndSettle();
        await enterPassphrase(tester, 'open sesame');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(called, isFalse);
        expect(find.byKey(const Key('restore-confirm')), findsNothing);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('wrong passphrase explains, restores nothing', (tester) async {
      final r = await liveDb();
      final bytes = await createBackup(
        db: r.db,
        attachments: AttachmentStore(r.docs),
        passphrase: 'open sesame',
        appVersion: appVersion,
        kdfIterations: 1000,
      );
      final io = FakeIo(PickedFile('trip.lzb', bytes));
      var called = false;
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          io: io,
          restore: (_) async => called = true,
        );
        await tapRow(tester, 'restore');
        await tester.pumpAndSettle();
        await enterPassphrase(tester, 'guess');
        expect(
          find.text(
            'Could not open that file — wrong passphrase, or it is damaged.',
          ),
          findsOneWidget,
        );
        expect(called, isFalse);
      } finally {
        await tearDownDb(r);
      }
    });
  });

  testWidgets('the Live FX toggle starts off and persists its state (§6)', (
    tester,
  ) async {
    final r = await liveDb();
    final fx = FxService(
      r.db,
      client: MockClient((_) async => http.Response('no', 500)),
    );
    try {
      await pumpManage(
        tester,
        repo: r.repo,
        db: r.db,
        docs: r.docs,
        fx: fx,
        liveFxVisible: true,
      );
      // Pro adds paid-pack rows above; mount the tile before reading it.
      await revealRow(tester, 'live-fx');
      // Default is off (opt-in, owner ruling 2026-11-11): a tap asks
      // first — the consent dialog names the endpoint and its payload.
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isFalse,
      );
      await tapRow(tester, 'live-fx');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('livefx-consent')), findsOneWidget);
      expect(find.textContaining('frankfurter.dev'), findsOneWidget);
      // A dialog still on screen has armed nothing.
      expect(await r.repo.setting(FxService.settingLiveFxRates), isNull);

      // Cancel: the switch never leaves off.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isFalse,
      );
      expect(await r.repo.setting(FxService.settingLiveFxRates), isNull);

      // Turn on: consented, armed, persisted.
      await tapRow(tester, 'live-fx');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('livefx-consent-go')));
      await tester.pumpAndSettle();
      expect(await r.repo.setting(FxService.settingLiveFxRates), 'on');
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isTrue,
      );

      await pumpManage(
        tester,
        repo: r.repo,
        db: r.db,
        docs: r.docs,
        fx: fx,
        liveFxVisible: true,
      );
      await revealRow(tester, 'live-fx');
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isTrue,
      );
      // Turning OFF needs no dialog — it only removes a permission.
      await tapRow(tester, 'live-fx');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('livefx-consent')), findsNothing);
      expect(await r.repo.setting(FxService.settingLiveFxRates), 'off');
    } finally {
      await tearDownDb(r);
    }
  });

  group('import wizard (§4/§5)', () {
    final csvBytes = Uint8List.fromList(
      utf8.encode(
        'Date,Description,Amount\n'
        '2026-11-01,Coffee Shop,4.75\n'
        '2026-11-02,Salary,2500.00\n',
      ),
    );

    const ofxText = '''
<?xml version="1.0" encoding="UTF-8"?>
<OFX>
  <BANKMSGSRSV1>
    <STMTTRNR>
      <STMTRS>
        <CURDEF>USD</CURDEF>
        <BANKTRANLIST>
          <DTSTART>20261101</DTSTART><DTEND>20261102</DTEND>
          <STMTTRN>
            <TRNTYPE>DEBIT</TRNTYPE>
            <DTPOSTED>20261102</DTPOSTED>
            <TRNAMT>-3.50</TRNAMT>
            <FITID>TXN0001</FITID>
            <NAME>CAFE LATE</NAME>
          </STMTTRN>
          <STMTTRN>
            <TRNTYPE>CREDIT</TRNTYPE>
            <DTPOSTED>20261101120000</DTPOSTED>
            <TRNAMT>2450.00</TRNAMT>
            <FITID>PAY0001</FITID>
            <NAME>ACME CORP PAYROLL</NAME>
          </STMTTRN>
        </BANKTRANLIST>
      </STMTRS>
    </STMTTRNR>
  </BANKMSGSRSV1>
</OFX>
''';

    testWidgets('CSV: map → preview → commit, profile remembered', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo(PickedFile('bank.csv', csvBytes));
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);
        await tapRow(tester, 'import-statement');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('import-account')), findsOneWidget);

        await tester.tap(find.byKey(const Key('import-pick-csv')));
        await tester.pumpAndSettle();
        // autoMap recognised the three headers; nothing left to set.
        expect(find.text('What is each column?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('import-preview-button')));
        await tester.pumpAndSettle();
        expect(find.text('2 new'), findsOneWidget);

        await tester.tap(find.byKey(const Key('import-commit')));
        await tester.pumpAndSettle();
        expect(find.text('Imported 2 transactions'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('profile-name-field')),
          'My bank',
        );
        await tester.tap(find.byKey(const Key('profile-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('import-close')));
        await tester.pumpAndSettle();

        final rows = await r.db.select(r.db.transactions).get();
        expect(rows, hasLength(2));
        expect(await CsvImport(r.db).profileNames(), contains('My bank'));
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('OFX skips the map step — the format carries its own mapping', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo(
        PickedFile('stmt.ofx', Uint8List.fromList(utf8.encode(ofxText))),
      );
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);
        await tapRow(tester, 'import-statement');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('import-pick-ofx')));
        await tester.pumpAndSettle();

        // Straight to Preview (§5): no column-mapping step.
        expect(find.text('What is each column?'), findsNothing);
        expect(find.text('2 new'), findsOneWidget);

        await tester.tap(find.byKey(const Key('import-commit')));
        await tester.pumpAndSettle();
        expect(find.text('Imported 2 transactions'), findsOneWidget);

        final rows = await r.db.select(r.db.transactions).get();
        expect(rows, hasLength(2));
        expect(rows.map((x) => x.source).toSet(), {
          TransactionSource.statementImport,
        });
      } finally {
        await tearDownDb(r);
      }
    });
  });

  group('document import (E11 §5)', () {
    // ≥ kStatementMinRows date+amount lines, no bill signature.
    final statementLines = const [
      '12/01/2026 CORNER MARKET 24.60 1,204.60',
      '12/03/2026 SALARY CREDIT 2,400.00 3,604.60',
      '12/05/2026 UTILITY AUTO PAY 84.00 3,520.60',
      '12/08/2026 COFFEE HOUSE 4.75 3,515.85',
    ];
    const billLines = [
      'ACME ELECTRIC',
      'AMOUNT DUE 84.00',
      'PAYMENT DUE DATE 01/15/2027',
    ];

    /// Manage → Import → the third row → one sheet choice, services faked.
    Future<void> openDocument(WidgetTester tester, String rowLabel) async {
      await tapRow(tester, 'import-statement');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-document')));
      await tester.pumpAndSettle();
      expect(find.text('Scan a bill or statement'), findsOneWidget);
      await tester.tap(find.text(rowLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('statement photo → same Preview and commit path as CSV', (
      tester,
    ) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          capture: docServices(lines: statementLines),
        );
        await openDocument(tester, 'Photos');
        // No column mapping — scanned lines arrive pre-parsed (§5).
        expect(find.text('What is each column?'), findsNothing);
        expect(find.byKey(const Key('import-document-note')), findsOneWidget);
        expect(
          find.textContaining(
            'Scanned rows are checked against what is already in the account.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('import-commit')));
        await tester.pumpAndSettle();
        expect(find.text('Imported 4 transactions'), findsOneWidget);

        final rows = await r.db.select(r.db.transactions).get();
        expect(rows, hasLength(4));
        expect(rows.map((x) => x.source).toSet(), {
          TransactionSource.statementImport,
        });
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('scanned PDF past the page cap says so on the preview', (
      tester,
    ) async {
      final r = await liveDb();
      // Pages 1–2 carry the rows; the fake rasterizer still hands over 12.
      final byTag = {
        1: statementLines.take(2).toList(),
        2: statementLines.skip(2).take(2).toList(),
      };
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          capture: docServices(byTag: byTag, scannedPages: 12),
        );
        await openDocument(tester, 'PDF file');
        expect(find.text('4 new'), findsOneWidget);
        expect(
          find.textContaining(
            'We read the first 10 pages of the PDF — '
            'later pages are not included.',
          ),
          findsOneWidget,
        );
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('bill photo → prefilled editor → “Bill saved.”, nothing '
        'written without the Save tap', (tester) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          capture: docServices(lines: billLines),
        );
        await openDocument(tester, 'Photos');
        expect(find.byKey(const Key('bill-prefill-note')), findsOneWidget);
        expect(
          find.text(
            'We read this from your document — check it before saving.',
          ),
          findsOneWidget,
        );
        final nameField = tester.widget<TextField>(
          find.byKey(const Key('bill-name')),
        );
        expect(nameField.controller!.text, 'ACME ELECTRIC');

        // The editor never invents a category — pick one (the row scrolls,
        // so tap the chip that is guaranteed built), then Save.
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('bill-categories')),
            matching: find.text('Food'),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('bill-save')));
        await tester.pumpAndSettle();
        expect(find.text('Bill saved.'), findsOneWidget);

        final rules = await r.db.select(r.db.recurringRules).get();
        expect(rules, hasLength(1));
        expect(rules.single.name, 'ACME ELECTRIC');
        expect(rules.single.amountMinor, 8400);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('a document that is neither points at CSV/OFX', (tester) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          capture: docServices(
            lines: const ['hello there', 'nothing readable', 'just words'],
          ),
        );
        await openDocument(tester, 'Photos');
        expect(
          find.textContaining('We couldn’t read a bill or a statement from it'),
          findsOneWidget,
        );
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('no readable text is an honest refusal, not a dead end', (
      tester,
    ) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          capture: docServices(lines: const []),
        );
        await openDocument(tester, 'Photos');
        expect(
          find.textContaining('We couldn’t read any text from it'),
          findsOneWidget,
        );
        // Still usable: the source panel is where we landed, not a crash.
        expect(find.byKey(const Key('import-pick-csv')), findsOneWidget);
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('the row is hidden entirely without capture services', (
      tester,
    ) async {
      final r = await liveDb();
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs);
        await tapRow(tester, 'import-statement');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('import-pick-document')), findsNothing);
      } finally {
        await tearDownDb(r);
      }
    });
  });

  group('QuickAdd rate stamp (§6)', () {
    Future<void> openQuickAddInEur(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('receipt-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('currency-button')));
      await tester.pumpAndSettle();
      // 33 codes, lazily built — EUR sits below the sheet's fold.
      await tester.dragUntilVisible(
        find.byKey(const Key('currency-EUR')),
        find.descendant(
          of: find.widgetWithText(BottomSheet, 'Entry currency'),
          matching: find.byType(ListView),
        ),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('currency-EUR')));
      await tester.pumpAndSettle();
      for (final k in ['1', '0', 'dot', '0', '0']) {
        await tester.tap(find.byKey(Key('keypad-$k')));
      }
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Food'),
        ),
      );
      await tester.pump();
    }

    testWidgets('a fetched rate stamps the row as base-per-unit and caches '
        'the provider quote', (tester) async {
      final r = await liveDb();
      final calls = <http.Request>[];
      final fx = FxService(
        r.db,
        client: MockClient((req) async {
          calls.add(req);
          return http.Response(
            '{"base":"USD","date":"$today","rates":{"EUR":0.93}}',
            200,
          );
        }),
      );
      await fx.setLiveRatesEnabled(true); // opt-in arms the fetch (§6)
      try {
        await tester.pumpWidget(
          LocalBudgetApp(repository: r.repo, db: r.db, fx: fx),
        );
        await tester.pumpAndSettle();
        await openQuickAddInEur(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        final row = (await r.db.select(r.db.transactions).get()).single;
        expect(row.currencyCode, 'EUR');
        expect(row.amountMinor, 1000);
        // 1 EUR in USD — the reciprocal of the provider quote (spec §6).
        expect(row.fxRate, closeTo(1 / 0.93, 1e-9));
        expect(row.baseAmountMinor, 1075);
        expect(calls.single.url.toString(), contains('base=USD'));
        // The cache stores the provider's own direction.
        expect(
          await r.repo.setting(FxService.cacheKey('USD', 'EUR', now)),
          '0.93',
        );
      } finally {
        await tearDownDb(r);
      }
    });

    testWidgets('a failed fetch still saves the row, flagged No rate', (
      tester,
    ) async {
      final r = await liveDb();
      final fx = FxService(
        r.db,
        client: MockClient((_) async => http.Response('down', 500)),
      );
      try {
        await tester.pumpWidget(
          LocalBudgetApp(repository: r.repo, db: r.db, fx: fx),
        );
        await tester.pumpAndSettle();
        await openQuickAddInEur(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        final row = (await r.db.select(r.db.transactions).get()).single;
        expect(row.currencyCode, 'EUR');
        expect(row.fxRate, isNull);
        expect(row.baseAmountMinor, isNull);
        expect(find.byKey(const Key('no-rate')), findsOneWidget);
      } finally {
        await tearDownDb(r);
      }
    });
  });

  testWidgets('tiles without a real app say so, never dead-end (§8 guard)', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await repo.setSetting('scannerConsent', 'fast'); // #56 gate: seeded answer
    try {
      await pumpManage(tester, repo: repo);
      for (final (key, what) in [
        ('export-csv', 'Export'),
        ('back-up', 'Backing up'),
        ('restore', 'Restoring'),
        ('import-statement', 'Importing'),
      ]) {
        await tapRow(tester, key);
        await tester.pumpAndSettle();
        expect(find.text('$what needs the real app.'), findsOneWidget);
        await expireSnack(tester);
      }
    } finally {
      await db.close();
    }
  });

  testWidgets('free builds do not offer a fetch they can never make (V-D26)', (
    tester,
  ) async {
    final r = await liveDb();
    final fx = FxService(r.db, client: MockClient((_) async => http.Response('no', 500)));
    try {
      await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, fx: fx);
      // Default liveFxVisible == FeatureFlags.proTrio == false in free
      // builds: the service is still wired (offline twin, stored rates),
      // but the toggle — and its promise — are not shown.
      expect(find.byKey(const Key('live-fx')), findsNothing);
    } finally {
      await r.db.close();
    }
  });
}
