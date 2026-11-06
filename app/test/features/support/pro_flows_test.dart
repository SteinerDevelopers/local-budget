// E6 §3 — free→paid data transfer through the [FakeFreeTransfer] seam:
// staging from the free app, pulling and confirming in Pro, and the honest
// refusal. The snapshot is a real `createBackup` envelope under the
// constant transfer passphrase — the same bytes the provider would serve.
//
// The pro-flavor rows hang off a const dart-define (flavor.dart), so those
// tests self-skip unless the file is run with --dart-define=APP_FLAVOR=pro
// (the free-flavor tests below assert the rows are NOT there instead).
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/manage/manage_screen.dart';
import 'package:local_budget/features/support/get_pro_page.dart';
import 'package:local_budget/features/support/transfer.dart';
import 'package:local_budget/flavor.dart';
import 'package:local_budget/version.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final isPro = appFlavor == AppFlavor.pro;

  /// A file-backed db + docs dir like a device (backup wants real WAL, and
  /// kdfIterations: 1000 keeps the KDF honest but instant — §8 seam).
  Future<({AppDatabase db, Directory docs, LedgerRepository repo})>
  liveDb() async {
    final docs = Directory.systemTemp.createTempSync('lzb_e6');
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

  Future<Uint8List> snapshotOf(
    ({AppDatabase db, Directory docs, LedgerRepository repo}) r,
  ) => createBackup(
    db: r.db,
    attachments: AttachmentStore(r.docs),
    passphrase: transferPassphrase,
    appVersion: appVersion,
    kdfIterations: 1000,
  );

  Future<void> pumpManage(
    WidgetTester tester, {
    required LedgerRepository repo,
    AppDatabase? db,
    Directory? docs,
    FreeTransfer? transfer,
    Future<void> Function(Backup backup)? restore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManageScreen(
          repository: repo,
          db: db,
          docsDir: docs,
          transfer: transfer,
          restore: restore,
          kdfIterations: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(ListView).first,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expireSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('Get Pro page (free flavor)', () {
    testWidgets('explains the separate app — trio, price, no unlock', (
      tester,
    ) async {
      final r = await liveDb();
      try {
        await pumpManage(tester, repo: r.repo, transfer: FakeFreeTransfer());
        await scrollTo(tester, find.byKey(const Key('get-pro')));
        await tester.tap(find.byKey(const Key('get-pro')));
        await tester.pumpAndSettle();

        expect(find.text('Personal cloud backup'), findsOneWidget);
        expect(find.text('Home-screen widgets'), findsOneWidget);
        expect(find.text('Advanced analytics'), findsOneWidget);
        expect(find.textContaining(r'$7.99 one-time'), findsOneWidget);
        expect(find.textContaining('not an unlock'), findsOneWidget);
        expect(find.text('Get it on Google Play'), findsOneWidget);
        // Decision 12: nothing inside the free app buys an unlock.
        expect(find.textContaining('Restore purchase'), findsNothing);
      } finally {
        await tearDownDb(r);
      }
    }, skip: isPro);

    testWidgets('Copy my data stages a snapshot Pro can open', (tester) async {
      final r = await liveDb();
      final fake = FakeFreeTransfer();
      try {
        final cash = await r.repo.defaultAccount();
        await r.repo.addTransaction(
          accountId: cash.id,
          date: DateTime(2026, 11, 1),
          amount: Money(1299, Currency.resolve('USD')),
          merchant: 'Stage Me',
          source: TransactionSource.manual,
        );
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          docs: r.docs,
          transfer: fake,
        );
        await scrollTo(tester, find.byKey(const Key('get-pro')));
        await tester.tap(find.byKey(const Key('get-pro')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Copy my data to Pro'), findsOneWidget);
        await tester.tap(find.byKey(const Key('pro-copy-data')));
        await tester.pumpAndSettle();

        final staged = fake.staged;
        expect(staged, isNotNull);
        // The provider hands these bytes out untouched; Pro opens them with
        // the compiled-in passphrase — assert that exact round trip here.
        final backup = openBackup(
          staged!,
          passphrase: transferPassphrase,
          currentSchemaVersion: r.db.schemaVersion,
        );
        expect(backup.databaseBytes, isNotEmpty);
        expect(backup.manifest.appVersion, appVersion);
        expect(
          find.textContaining('Copied. Open Steiner Budget Pro'),
          findsOneWidget,
        );
        await expireSnack(tester);
      } finally {
        await tearDownDb(r);
      }
    }, skip: isPro);

    testWidgets('the transfer row is not a free-app feature', (tester) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          transfer: FakeFreeTransfer(free: true, snapshot: Uint8List(9)),
        );
        await scrollTo(tester, find.text('About & help'));
        expect(find.byKey(const Key('transfer-free')), findsNothing);
      } finally {
        await tearDownDb(r);
      }
    }, skip: isPro);
  });

  group('GetProPage channel awareness', () {
    testWidgets('says Pro is installed once the channel sees it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GetProPage(
            transfer: FakeFreeTransfer(pro: true),
            onCopyData: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The note sits under the fold on a phone viewport; ListView is lazy,
      // so it must be scrolled into the cache extent before it exists.
      await tester.dragUntilVisible(
        find.byKey(const Key('pro-installed-note')),
        find.byType(ListView),
        const Offset(0, -120),
      );
      expect(find.text('Pro installed — open it to transfer.'), findsOneWidget);
    });

    testWidgets('stays quiet when Pro is not installed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GetProPage(
            transfer: FakeFreeTransfer(),
            onCopyData: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Scroll to the page footer first so "not found" can't hide behind
      // the lazy viewport.
      await tester.dragUntilVisible(
        find.textContaining('any path works'),
        find.byType(ListView),
        const Offset(0, -120),
      );
      expect(find.byKey(const Key('pro-installed-note')), findsNothing);
    });
  });

  group('Transfer from free app (pro flavor)', () {
    testWidgets('appears when the free app resolves, with snapshot age', (
      tester,
    ) async {
      final r = await liveDb();
      final src = await liveDb();
      try {
        final bytes = await snapshotOf(src);
        await pumpManage(
          tester,
          repo: r.repo,
          transfer: FakeFreeTransfer(free: true, snapshot: bytes),
        );
        await scrollTo(tester, find.byKey(const Key('transfer-free')));
        expect(find.text('Transfer from free app'), findsOneWidget);
        // FakeFreeTransfer fixes mtime (2025-10-31) — age must be stated,
        // never implied live (§3 freshness honesty).
        expect(find.textContaining('Data staged on '), findsOneWidget);
      } finally {
        await tearDownDb(src);
        await tearDownDb(r);
      }
    }, skip: !isPro);

    testWidgets('says so when nothing is staged yet', (tester) async {
      final r = await liveDb();
      try {
        await pumpManage(
          tester,
          repo: r.repo,
          transfer: FakeFreeTransfer(free: true),
        );
        await scrollTo(tester, find.byKey(const Key('transfer-free')));
        expect(find.text('Nothing staged yet in the free app'), findsOneWidget);
      } finally {
        await tearDownDb(r);
      }
    }, skip: !isPro);

    testWidgets('confirm replaces everything via the one restore path', (
      tester,
    ) async {
      final r = await liveDb();
      final src = await liveDb();
      final restored = <Backup>[];
      try {
        final cash = await src.repo.defaultAccount();
        await src.repo.addTransaction(
          accountId: cash.id,
          date: DateTime(2026, 10, 20),
          amount: Money(4200, Currency.resolve('USD')),
          merchant: 'From Free',
          source: TransactionSource.manual,
        );
        final fake = FakeFreeTransfer(
          free: true,
          snapshot: await snapshotOf(src),
        );
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          restore: (b) async => restored.add(b),
          transfer: fake,
        );
        await scrollTo(tester, find.byKey(const Key('transfer-free')));
        await tester.tap(find.byKey(const Key('transfer-free')));
        await tester.pumpAndSettle();

        expect(find.text('Replace everything?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('transfer-go')));
        await tester.pumpAndSettle();

        // The real openBackup ran (constant passphrase, current schema) and
        // the bytes reached the cold-restart restore unchanged.
        expect(restored, hasLength(1));
        expect(restored.single.databaseBytes, isNotEmpty);
        expect(restored.single.manifest.appVersion, appVersion);
      } finally {
        await tearDownDb(src);
        await tearDownDb(r);
      }
    }, skip: !isPro);

    testWidgets('Cancel keeps the ledger and says nothing more', (
      tester,
    ) async {
      final r = await liveDb();
      final src = await liveDb();
      final restored = <Backup>[];
      try {
        final fake = FakeFreeTransfer(
          free: true,
          snapshot: await snapshotOf(src),
        );
        await pumpManage(
          tester,
          repo: r.repo,
          db: r.db,
          restore: (b) async => restored.add(b),
          transfer: fake,
        );
        await scrollTo(tester, find.byKey(const Key('transfer-free')));
        await tester.tap(find.byKey(const Key('transfer-free')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(restored, isEmpty);
        expect(find.text('Replace everything?'), findsNothing);
      } finally {
        await tearDownDb(src);
        await tearDownDb(r);
      }
    }, skip: !isPro);

    testWidgets('a damaged or missing snapshot falls back honestly (§6)', (
      tester,
    ) async {
      final cases = <Uint8List?>[
        null,
        Uint8List.fromList([1, 2, 3]),
      ];
      for (final snapshot in cases) {
        final r = await liveDb();
        try {
          await pumpManage(
            tester,
            repo: r.repo,
            db: r.db,
            restore: (_) async {},
            transfer: FakeFreeTransfer(free: true, snapshot: snapshot),
          );
          await scrollTo(tester, find.byKey(const Key('transfer-free')));
          await tester.tap(find.byKey(const Key('transfer-free')));
          await tester.pumpAndSettle();

          expect(
            find.text(
              "Couldn't read from the free app. You can still use an "
              'exported backup file.',
            ),
            findsOneWidget,
          );
          expect(find.text('Replace everything?'), findsNothing);
          await expireSnack(tester);
        } finally {
          await tearDownDb(r);
        }
      }
    }, skip: !isPro);
  });
}
