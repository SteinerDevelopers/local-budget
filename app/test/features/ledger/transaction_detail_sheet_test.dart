// E2 §4 + listing promise ("attachments live with the entry, so 'what was
// this?' has a picture as an answer"): a row saved with a scanned original
// shows a thumbnail in the detail sheet, and the thumbnail opens a
// full-screen viewer. Rows without one render exactly as before.
import 'dart:convert' show base64Decode;
import 'dart:ffi' show DynamicLibrary;
import 'dart:io' show Directory;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf;
import 'package:local_budget/features/ledger/transaction_detail_sheet.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');

  // 1×1 red PNG.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  Future<void> openDetail(
    WidgetTester tester,
    LedgerRepository repo,
    LedgerEntryData entry,
    AttachmentStore? store,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTransactionDetail(
                context,
                repository: repo,
                entry: entry,
                baseCode: 'USD',
                attachments: store,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('detail attachment (§4, listing)', () {
    testWidgets('a row with an original shows the thumb and opens the viewer', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('attach-test');
      final db = AppDatabase.inMemory();
      final repo = LedgerRepository(db);
      try {
        await repo.ensureDefaults();
        final store = AttachmentStore(dir);
        final rel = store.saveOriginal(
          png,
          extension: 'png',
          source: TransactionSource.cameraScan,
        );
        final acc = await repo.defaultAccount();
        final cat = (await repo.categories()).first;
        await repo.addTransaction(
          accountId: acc.id,
          date: DateTime(2026, 9, 11),
          amount: Money(6993, usd),
          source: TransactionSource.cameraScan,
          categoryId: cat.id,
          imageRef: rel,
        );
        final entries = await repo.watchMonth(monthIndexOf(DateTime(2026, 9, 15))).first;
        final entry = entries.single;
        expect(entry.imageRef, rel); // the projection carries it now

        await openDetail(tester, repo, entry, store);
        expect(find.byKey(const Key('detail-attachment-thumb')), findsOneWidget);

        await tester.tap(find.byKey(const Key('detail-attachment')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('photo-viewer-image')), findsOneWidget);

        await tester.tap(find.byKey(const Key('photo-close')));
        await tester.pumpAndSettle();
        // back on the sheet, not on a viewer
        expect(find.byKey(const Key('photo-viewer-image')), findsNothing);
        expect(find.byKey(const Key('detail-attachment-thumb')), findsOneWidget);
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    });

    testWidgets('no original, no thumbnail (renders as before)', (tester) async {
      final db = AppDatabase.inMemory();
      final repo = LedgerRepository(db);
      try {
        await repo.ensureDefaults();
        final acc = await repo.defaultAccount();
        final cat = (await repo.categories()).first;
        await repo.addTransaction(
          accountId: acc.id,
          date: DateTime(2026, 9, 11),
          amount: Money(500, usd),
          source: TransactionSource.manual,
          categoryId: cat.id,
        );
        final entry = (await repo
                .watchMonth(monthIndexOf(DateTime(2026, 9, 15))))
            .first
            .single;
        final dir = Directory.systemTemp.createTempSync('attach-none');
        try {
          await openDetail(tester, repo, entry, AttachmentStore(dir));
          expect(
            find.byKey(const Key('detail-attachment-thumb')),
            findsNothing,
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      } finally {
        await db.close();
      }
    });
  });
}
