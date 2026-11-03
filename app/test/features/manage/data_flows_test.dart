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

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_budget/features/manage/io.dart';
import 'package:local_budget/features/manage/manage_screen.dart';
import 'package:local_budget/main.dart';
import 'package:local_budget/version.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class FakeIo implements Io {
  FakeIo([this.pickResult]);

  PickedFile? pickResult;
  final shared = <(Uint8List bytes, String name)>[];

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async => pickResult;

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
  }) async => shared.add((bytes, fileName));
}

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
    FxService? fx,
    Future<void> Function(Backup backup)? restore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManageScreen(
          repository: repo,
          db: db,
          docsDir: docs,
          io: io ?? FakeIo(),
          fx: fx,
          restore: restore,
          kdfIterations: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();
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

        await tester.tap(find.byKey(const Key('export-csv')));
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

        await tester.tap(find.byKey(const Key('export-csv')));
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
    testWidgets('passphrase twice, then an LZBK1 file to share', (
      tester,
    ) async {
      final r = await liveDb();
      final io = FakeIo();
      try {
        await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, io: io);

        await tester.tap(find.byKey(const Key('back-up')));
        await tester.pumpAndSettle();
        expect(
          find.text('Choose a passphrase for this backup'),
          findsOneWidget,
        );
        await enterPassphrase(tester, 'right horse battery', withConfirm: true);

        expect(io.shared, hasLength(1));
        final (bytes, name) = io.shared.single;
        expect(name, matches(r'^localbudget-backup-\d{4}-\d{2}-\d{2}\.lzb$'));
        expect(utf8.decode(bytes.sublist(0, 5)), 'LZBK1');
        expect(
          find.textContaining('Backup ready to share as $name'),
          findsOneWidget,
        );
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
        await tester.tap(find.byKey(const Key('back-up')));
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

        await tester.tap(find.byKey(const Key('restore')));
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
        await tester.tap(find.byKey(const Key('restore')));
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
        await tester.tap(find.byKey(const Key('restore')));
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

  testWidgets('the Live FX toggle persists its off state (§6)', (tester) async {
    final r = await liveDb();
    final fx = FxService(
      r.db,
      client: MockClient((_) async => http.Response('no', 500)),
    );
    try {
      await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, fx: fx);
      // Default is on (§6), so a tap means off.
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('live-fx')));
      await tester.pumpAndSettle();
      expect(await r.repo.setting(FxService.settingLiveFxRates), 'off');

      await pumpManage(tester, repo: r.repo, db: r.db, docs: r.docs, fx: fx);
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('live-fx'))).value,
        isFalse,
      );
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
        await tester.tap(find.byKey(const Key('import-statement')));
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
        await tester.tap(find.byKey(const Key('import-statement')));
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

  group('QuickAdd rate stamp (§6)', () {
    Future<void> openQuickAddInEur(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('fab-quickadd')));
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
    try {
      await pumpManage(tester, repo: repo);
      for (final (key, what) in [
        ('export-csv', 'Export'),
        ('back-up', 'Backing up'),
        ('restore', 'Restoring'),
        ('import-statement', 'Importing'),
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.text('$what needs the real app.'), findsOneWidget);
        await expireSnack(tester);
      }
    } finally {
      await db.close();
    }
  });
}
