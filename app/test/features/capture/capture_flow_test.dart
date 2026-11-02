// E2 capture flow, app side (#27): source sheet → fake intake/extractor →
// Review → exactly one transaction (or zero). Everything is hermetic (§7):
// the TextExtractor fake replaces OCR and the AttachmentStore points at a
// temp dir — no camera, no ML Kit, nothing outside the process.
import 'dart:convert' show base64Decode;
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart' show TransactionSource;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/capture_services.dart';
import 'package:local_budget/features/capture/review_sheet.dart';
import 'package:local_budget/features/ledger/transaction_row.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

// Minimal decodable 1×1 PNG — the strip renders it; the fake extractor
// ignores the bytes entirely.
final Uint8List kPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDw'
  'AChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeExtractor implements TextExtractor {
  _FakeExtractor(this.lines);
  final List<String> lines;
  @override
  Future<List<String>> extractText(Uint8List imageBytes) async => lines;
}

class _FakeIntake implements CaptureIntake {
  _FakeIntake({this.cancel = false, this.showScreenshot = true});
  final bool cancel;
  final bool showScreenshot;
  @override
  bool get hasScreenshotRow => showScreenshot;
  @override
  Future<CapturePick?> pick(CaptureChoice choice) async =>
      cancel ? null : CapturePick(bytes: kPng, choice: choice);
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory storeRoot;

  setUp(() => storeRoot = Directory.systemTemp.createTempSync('attach'));
  tearDown(() => storeRoot.deleteSync(recursive: true));

  List<FileSystemEntity> attachmentFiles() {
    final d = Directory('${storeRoot.path}/attachments');
    return d.existsSync() ? d.listSync() : const [];
  }

  CaptureServices services({
    List<String> lines = const [
      'GREENGROCER MARKET',
      '2026-10-28',
      'TOTAL 12.34',
    ],
    bool cancel = false,
    bool showScreenshot = true,
  }) => CaptureServices(
    intake: _FakeIntake(cancel: cancel, showScreenshot: showScreenshot),
    extractor: _FakeExtractor(lines),
    store: AttachmentStore(storeRoot),
  );

  Future<({AppDatabase db, LedgerRepository repo})> pumpCapture(
    WidgetTester tester,
    CaptureServices capture,
  ) async {
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await tester.pumpWidget(LocalBudgetApp(repository: repo, capture: capture));
    await tester.pumpAndSettle();
    return (db: db, repo: repo);
  }

  Future<void> openSourceSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('fab-capture')));
    await tester.pumpAndSettle();
  }

  /// Source sheet → Camera → Review sheet, extraction settled.
  Future<void> openReview(WidgetTester tester) async {
    await openSourceSheet(tester);
    await tester.tap(find.byKey(const Key('capture-camera')));
    await tester.pumpAndSettle();
  }

  Future<void> pressKeys(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      await tester.tap(find.byKey(Key('keypad-${k == '.' ? 'dot' : k}')));
      await tester.pump();
    }
  }

  testWidgets('secondary FAB opens the source sheet with the decision-5 line', (
    tester,
  ) async {
    final ctx = await pumpCapture(tester, services());
    try {
      await openSourceSheet(tester);
      expect(find.text('Add from receipt'), findsOneWidget);
      expect(
        find.text('One receipt at a time — you review before it’s saved.'),
        findsOneWidget,
      );
      for (final name in ['camera', 'photos', 'pdf', 'screenshot']) {
        expect(find.byKey(Key('capture-$name')), findsOneWidget);
      }
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('screenshot row hides when the platform cannot offer it', (
    tester,
  ) async {
    final ctx = await pumpCapture(tester, services(showScreenshot: false));
    try {
      await openSourceSheet(tester);
      expect(find.byKey(const Key('capture-screenshot')), findsNothing);
      expect(find.byKey(const Key('capture-camera')), findsOneWidget);
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('cancelled picker leaves the ledger untouched (§2.1)', (
    tester,
  ) async {
    final ctx = await pumpCapture(tester, services(cancel: true));
    try {
      await openSourceSheet(tester);
      await tester.tap(find.byKey(const Key('capture-camera')));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureReviewSheet), findsNothing);
      expect(find.byType(TransactionRow), findsNothing);
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('review prefills amount, date, merchant; gate needs a category', (
    tester,
  ) async {
    final ctx = await pumpCapture(tester, services());
    try {
      await openReview(tester);
      expect(find.byType(CaptureReviewSheet), findsOneWidget);
      expect(find.text('12.34'), findsOneWidget); // AmountPad display
      expect(find.textContaining('28 Oct'), findsOneWidget); // date strip
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'GREENGROCER MARKET',
      );
      expect(find.text('Scan'), findsOneWidget); // source badge

      // Gate parity with QuickAdd: amount ok but no category → Save dead.
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);

      await tester.tap(find.widgetWithText(FilterChip, 'Food'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(TransactionRow), findsOneWidget);
      final row = await ctx.db
          .customSelect(
            'SELECT image_ref, source, merchant_id FROM transactions',
          )
          .getSingle();
      expect(row.data['image_ref'], startsWith('attachments/'));
      expect(row.data['source'], TransactionSource.cameraScan.wireName);
      expect(row.data['merchant_id'], isNotNull); // merchant upserted
      final file = '${storeRoot.path}/${row.data['image_ref']}';
      expect(File(file).existsSync(), isTrue);
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('ambiguous date + low-confidence amount flag; edit clears', (
    tester,
  ) async {
    final ctx = await pumpCapture(
      tester,
      services(lines: const ['CORNER STORE', '03/04/2026', 'AMOUNT 9.50']),
    );
    try {
      await openReview(tester);
      expect(find.text('9.5'), findsOneWidget); // filled from low-conf total
      expect(find.text('Day and month are unclear — check.'), findsOneWidget);
      expect(find.text('Check amount'), findsOneWidget);

      final handle = tester.ensureSemantics();
      // §5: TalkBack suffixes each flagged field.
      expect(
        find.descendant(
          of: find.byType(CaptureReviewSheet),
          matching: find.bySemanticsLabel(
            RegExp('Amount — needs checking|Date — needs checking'),
          ),
        ),
        findsNWidgets(2),
      );

      // First user edit clears the amount flag (§2.3 2.) — and only it.
      await pressKeys(tester, '5');
      await tester.pump();
      expect(find.text('Check amount'), findsNothing);
      expect(find.bySemanticsLabel('Amount — needs checking'), findsNothing);
      expect(find.text('Day and month are unclear — check.'), findsOneWidget);
      handle.dispose();
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('no total found opens the pad empty with its helper', (
    tester,
  ) async {
    final ctx = await pumpCapture(
      tester,
      services(lines: const ['THANK YOU FOR VISITING']),
    );
    try {
      await openReview(tester);
      expect(find.text('No total found — type it in.'), findsOneWidget);
      // Pad placeholder (not a keypad digit): the keyed display reads '0'.
      expect(
        tester.widget<Text>(find.byKey(const Key('amount-value'))).data,
        '0',
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets('discard writes nothing — no row, no file', (tester) async {
    final ctx = await pumpCapture(tester, services());
    try {
      await openReview(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureReviewSheet), findsNothing);
      expect(find.byType(TransactionRow), findsNothing);
      expect(attachmentFiles(), isEmpty);
    } finally {
      await ctx.db.close();
    }
  });

  testWidgets(
    'delete unlinks the attachment; undo restores the row without it',
    (tester) async {
      final ctx = await pumpCapture(tester, services());
      try {
        await openReview(tester);
        await tester.tap(find.widgetWithText(FilterChip, 'Food'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        await tester.timedDrag(
          find.byType(TransactionRow),
          const Offset(-600, 0),
          const Duration(milliseconds: 100),
        );
        await tester.pumpAndSettle(); // commit + SnackBar
        expect(find.byType(TransactionRow), findsNothing);

        final rows = await ctx.db
            .customSelect('SELECT image_ref FROM transactions')
            .get();
        expect(rows, isEmpty); // row gone…
        expect(attachmentFiles(), isEmpty); // …and so is its file (§4)

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        final restored = await ctx.db
            .customSelect('SELECT image_ref FROM transactions')
            .getSingle();
        expect(
          restored.data['image_ref'],
          isNull,
        ); // row back, image not re-saved
        expect(find.byType(TransactionRow), findsOneWidget);
      } finally {
        await ctx.db.close();
      }
    },
  );
}
