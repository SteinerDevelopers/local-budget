// E2 §4 + the listing promise ("attachments live with the entry, so
// 'what was this?' has a picture as an answer"): a row saved with a
// scanned original shows a thumbnail in the detail sheet, and the
// thumbnail opens a full-screen viewer. Rows without one render exactly
// as before. Same drift rules as detail_sheet_test.dart: db.close()
// INSIDE the test body, and the ledger stream is pumped through the app
// (never awaited directly in the fake-async zone).
import 'dart:convert' show base64Decode;
import 'dart:ffi' show DynamicLibrary;
import 'dart:io' show Directory;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/capture_services.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

/// The detail path never touches intake; it only needs the store.
class _NoIntake implements CaptureIntake {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnsupportedError('unused');
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');

  // A real (1×1 red) PNG: the viewer renders from the actual file.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
  });

  Future<int> seed({String? imageRef}) async {
    await repo.ensureDefaults();
    final account = await repo.defaultAccount();
    final cats = await repo.categories();
    return repo.addTransaction(
      accountId: account.id,
      date: DateTime.now(),
      amount: Money(6993, usd),
      source: TransactionSource.cameraScan,
      categoryId: cats.first.id,
      imageRef: imageRef,
    );
  }

  Future<void> pumpLedger(WidgetTester tester, AttachmentStore store) async {
    await tester.pumpWidget(
      LocalBudgetApp(
        repository: repo,
        capture: CaptureServices(intake: _NoIntake(), store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('detail attachment (§4, listing)', () {
    testWidgets('a row with an original shows the thumb and opens the viewer',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('attach-test');
      try {
        final rel =
            AttachmentStore(dir).saveOriginal(
              png,
              extension: 'png',
              source: TransactionSource.cameraScan,
            );
        await seed(imageRef: rel);
        await pumpLedger(tester, AttachmentStore(dir));

        await tester.tap(find.text('Food').first); // open the detail
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('detail-attachment-thumb')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('detail-attachment')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('photo-viewer-image')), findsOneWidget);

        await tester.tap(find.byKey(const Key('photo-close')));
        await tester.pumpAndSettle();
        // Back on the sheet with the thumb; the viewer is gone.
        expect(find.byKey(const Key('photo-viewer-image')), findsNothing);
        expect(
          find.byKey(const Key('detail-attachment-thumb')),
          findsOneWidget,
        );
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    });

    testWidgets('no original, no thumbnail (renders as before)', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('attach-none');
      try {
        await seed(); // manual row, no imageRef
        await pumpLedger(tester, AttachmentStore(dir));
        await tester.tap(find.text('Food').first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('detail-attachment-thumb')),
          findsNothing,
        );
        // and the sheet itself is the normal one
        expect(find.byKey(const Key('detail-delete')), findsOneWidget);
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    });
  });
}
