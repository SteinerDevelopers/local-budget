// Measurement-day follow-through (bench 2026-11-10, MR !5 bank): the free
// flavor without Gemini Nano lands EVERY bench scan on the manual review
// path — "No total found — type it in." — and that path carries the beta's
// worst-case flow (median 32.9 s Flip6 / 45.1 s VERGE) with zero CI
// coverage. These tests pin it end-to-end (work item 3) and pin both halves
// of the Save gate (work item 2: `_canSave = money.isPositive &&
// _categoryId != null`, review_sheet.dart) — our own bench instruments
// burned three passes discovering the gate by hand.
//
// Hermetic per §7: fake intake/extractor, temp-dir AttachmentStore — no
// camera, no ML Kit. Harness conventions copied from capture_flow_test.dart
// (plain get(), never watch().first in a test body).
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

final Uint8List kPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDw'
  'AChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A TOTAL-less receipt line set — exactly what the bench corpus fixtures
/// look like to the Tier-1/Tier-2 (no-Nano) pipeline: merchant-ish first
/// line, no total the parser can commit to.
const List<String> kNoTotalLines = [
  'CORNER CAFE',
  '2026-11-09',
  'LATTE 4.00',
  'COBBLESTONE 5.25',
];

class _FakeExtractor implements TextExtractor {
  _FakeExtractor(this.lines);
  final List<String> lines;
  @override
  Future<List<String>> extractText(Uint8List imageBytes) async => lines;
}

class _FakeIntake implements CaptureIntake {
  _FakeIntake({this.showScreenshot = true});
  final bool showScreenshot;
  @override
  bool get hasScreenshotRow => showScreenshot;
  @override
  Future<CapturePick?> pick(CaptureChoice choice) async =>
      CapturePick(bytes: kPng, choice: choice);
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory storeRoot;
  setUp(() => storeRoot = Directory.systemTemp.createTempSync('manualpath'));
  tearDown(() => storeRoot.deleteSync(recursive: true));

  CaptureServices services({bool showScreenshot = true}) => CaptureServices(
    intake: _FakeIntake(showScreenshot: showScreenshot),
    extractor: _FakeExtractor(kNoTotalLines),
    store: AttachmentStore(storeRoot),
  );

  Future<({AppDatabase db, LedgerRepository repo})> pumpCapture(
    WidgetTester tester, {
    bool showScreenshot = true,
  }) async {
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await tester.pumpWidget(
      LocalBudgetApp(
        repository: repo,
        capture: services(showScreenshot: showScreenshot),
      ),
    );
    await tester.pumpAndSettle();
    return (db: db, repo: repo);
  }

  Future<void> openReview(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('receipt-add-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-camera')));
    await tester.pumpAndSettle();
  }

  Future<void> pressKeys(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      final key = find.byKey(Key('keypad-${k == '.' ? 'dot' : k}'));
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      await tester.tap(key);
      await tester.pump();
    }
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

  group('manual review path — total-less receipt (bench §4.5 evidence)', () {
    testWidgets('chip alone does not arm Save; amount then chip does', (
      tester,
    ) async {
      final ctx = await pumpCapture(tester);
      try {
        await openReview(tester);
        expect(find.byType(CaptureReviewSheet), findsOneWidget);
        // The exact bench copy (free flavor, no Nano): reviewed 2026-11-10.
        expect(find.text('No total found — type it in.'), findsOneWidget);

        // Half 1: a category chip alone must not arm Save.
        await tester.tap(find.widgetWithText(FilterChip, 'Food'));
        await tester.pump();
        expect(saveButton(tester).onPressed, isNull, reason: '_canSave');

        // Then the amount completes the AND.
        await pressKeys(tester, '5.00');
        expect(saveButton(tester).onPressed, isNotNull, reason: 'both halves');
      } finally {
        await ctx.db.close();
      }
    });

    testWidgets('amount alone does not arm Save; chip then arms', (
      tester,
    ) async {
      // The other order gets its own pump: the review sheet is a
      // barrier-locked bottom sheet (bench-proven: no scrim tap-out), so a
      // mid-test reset would fake a flow the user cannot take.
      final ctx = await pumpCapture(tester);
      try {
        await openReview(tester);
        await pressKeys(tester, '5.00');
        expect(
          saveButton(tester).onPressed,
          isNull,
          reason: 'chip missing — the bench three-pass lesson',
        );
        await tester.tap(find.widgetWithText(FilterChip, 'Food'));
        await tester.pump();
        expect(saveButton(tester).onPressed, isNotNull);
      } finally {
        await ctx.db.close();
      }
    });

    testWidgets('typed amount + chip commits exactly one camera_scan row', (
      tester,
    ) async {
      final ctx = await pumpCapture(tester);
      try {
        await openReview(tester);
        await pressKeys(tester, '9.25');
        await tester.tap(find.widgetWithText(FilterChip, 'Food'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(find.byType(CaptureReviewSheet), findsNothing);
        expect(find.byType(TransactionRow), findsOneWidget);
        final rows = await ctx.db
            .customSelect(
              'SELECT amount_minor, source, image_ref FROM transactions',
            )
            .get();
        expect(rows.length, 1, reason: 'one review, one row — never two');
        expect(rows.single.data['amount_minor'], 925);
        expect(
          rows.single.data['source'],
          TransactionSource.cameraScan.wireName,
        );
        expect(rows.single.data['image_ref'], startsWith('attachments/'));
        expect(
          File(
            '${storeRoot.path}/${rows.single.data['image_ref'] as String}',
          ).existsSync(),
          isTrue,
        );
      } finally {
        await ctx.db.close();
      }
    });
  });

  group('capture sheets at 2.0 text scale (device-measured 2026-11-10)', () {
    // Origin story (2026-11-10): the overnight "Finding 2" claimed the
    // QuickAdd sheet clipped at 2.0 on both phones — re-adjudication
    // against the same banked pixels REVERSED it (intact $0, scrollbar
    // thumb misread as the cut, partial chip = scroll affordance). What
    // these guards did surface were two real layout bugs the widget
    // suite caught and no bench leg could: the conditional 'Recent
    // screenshot' row (hidden on bench devices) and the review sheet's
    // missing font-scale escape. Both fixed in this MR.
    Future<void> scaleUp2(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
      'source chooser at 360 dp / 2.0 renders without overflow',
      (tester) async {
        final ctx = await pumpCapture(tester);
        try {
          await scaleUp2(tester);
          await tester.tap(find.byKey(const ValueKey('receipt-add-document')));
          await tester.pumpAndSettle();
          expect(find.text('Add from receipt'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await ctx.db.close();
        }
      },
      // Real CI-found bug (never device-observable on the bench — the row
      // hides without a recent screenshot): the 17-char label spilled the
      // fixed Row by 260 px at 2.0. Fixed with the scaleDown precedent
      // (Expanded + FittedBox, AmountDisplay §5 pattern) in this MR.
    );

    testWidgets(
      'manual review sheet at 360 dp / 2.0 renders without overflow',
      (tester) async {
        // showScreenshot:false mirrors the bench row-hiding so the parked
        // chooser bug above cannot mask this guard.
        final ctx = await pumpCapture(tester, showScreenshot: false);
        try {
          await scaleUp2(tester);
          await openReview(tester);
          await pressKeys(tester, '9.25');
          expect(tester.takeException(), isNull);
        } finally {
          await ctx.db.close();
        }
      },
      // Real CI-found bug: the fixed portrait stack (strip + fields +
      // keypad-min + chips + toggle + Save) spilled the 92 % sheet by
      // 104 px at 2.0 — the sheet had no font-scale escape (QuickAdd got
      // one 2026-11-04; review missed the family fix). Fixed here: strip
      // + fields became the scrollable region; controls stay pinned.
    );
  });
}
