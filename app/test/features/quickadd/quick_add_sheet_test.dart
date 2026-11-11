import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/view_models.dart';
import 'package:local_budget/features/quickadd/quick_add_draft.dart';
import 'package:local_budget/features/quickadd/quick_add_sheet.dart';

const _cats = [
  CategoryOption(1, 'Food', Icons.local_cafe_outlined),
  CategoryOption(2, 'Rent', Icons.home_outlined),
];
final _usd = Currency.resolve('USD');

void main() {
  late NewEntry? result;
  int manageTaps = 0;

  /// Host app whose button opens the sheet exactly like the Ledger will (#17);
  /// the awaited pop value lands in [result].
  Future<void> openSheet(
    WidgetTester tester, {
    EntryKind initialKind = EntryKind.expense,
    int? initialCategoryId,
    QuickAddDraft? draft,
    void Function(QuickAddDraft)? onDraft,
  }) async {
    result = null;
    manageTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showQuickAdd(
                  context,
                  categories: _cats,
                  currency: _usd,
                  initialKind: initialKind,
                  initialCategoryId: initialCategoryId,
                  draft: draft,
                  onDraftChanged: onDraft,
                  onManageCategories: () => manageTaps++,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key('keypad-$key')));
    await tester.pump();
  }

  String amountText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('amount-value'))).data!;

  void expectSaveEnabled(WidgetTester tester, bool enabled) {
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed != null, enabled, reason: 'Save enabled?');
  }

  group('QuickAdd sheet (§2.2)', () {
    testWidgets('cold open: Expense preselected, Save gated, dimmed 0', (
      tester,
    ) async {
      await openSheet(tester);
      final seg = tester.widget<SegmentedButton<EntryKind>>(
        find.byType(SegmentedButton<EntryKind>),
      );
      expect(seg.selected, {EntryKind.expense});
      expect(amountText(tester), '0'); // placeholder, not a keypad press
      expect(find.text('\$'), findsOneWidget); // currency symbol
      expectSaveEnabled(tester, false);
      // no system keyboard anywhere: the amount is not a TextField
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('amount alone does not unlock Save; category does', (
      tester,
    ) async {
      await openSheet(tester);
      for (final k in ['1', '2', 'dot', '4']) {
        await press(tester, k);
      }
      expect(amountText(tester), '12.4');
      expectSaveEnabled(tester, false); // no category yet

      await tester.tap(find.text('Food'));
      await tester.pump();
      expectSaveEnabled(tester, true);
    });

    testWidgets('Save returns an exact NewEntry and pops', (tester) async {
      await openSheet(tester);
      for (final k in ['1', '2', 'dot', '4', '0']) {
        await press(tester, k);
      }
      await tester.tap(find.text('Food'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<EntryKind>), findsNothing); // popped
      expect(result, isNotNull);
      expect(result!.kind, EntryKind.expense);
      expect(result!.categoryId, 1);
      expect(result!.amount, Money(1240, _usd));
      expect(result!.note, isNull);
      final now = DateTime.now();
      expect(result!.day.year, now.year);
      expect(result!.day.month, now.month);
      expect(result!.day.day, now.day);
    });

    testWidgets('warm open carries kind + category (§2.2 item 5)', (
      tester,
    ) async {
      await openSheet(
        tester,
        initialKind: EntryKind.income,
        initialCategoryId: 2,
      );
      final seg = tester.widget<SegmentedButton<EntryKind>>(
        find.byType(SegmentedButton<EntryKind>),
      );
      expect(seg.selected, {EntryKind.income});
      final rentChip = tester.widget<FilterChip>(
        find.ancestor(of: find.text('Rent'), matching: find.byType(FilterChip)),
      );
      expect(rentChip.selected, isTrue);
    });

    testWidgets('backspace edits, gear chip jumps to Manage', (tester) async {
      await openSheet(tester);
      await press(tester, '9');
      expect(amountText(tester), '9');
      await press(tester, 'back');
      expect(amountText(tester), '0'); // back to placeholder

      await tester.tap(find.byIcon(Icons.settings_outlined));
      // #18: the gear now pops the sheet before jumping — settle the exit.
      await tester.pumpAndSettle();
      expect(manageTaps, 1);
    });

    testWidgets('date strip: Yesterday sets the entry day', (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Calendar…'), findsOneWidget); // strip revealed

      await tester.tap(find.text('Yesterday'));
      await tester.pump();
      expect(find.text('Today'), findsNothing); // strip closed, label moved

      await press(tester, '5');
      await tester.tap(find.text('Rent'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(result!.day.day, yesterday.day);
      expect(result!.amount, Money(500, _usd));
    });

    testWidgets('calendar pick collapses the strip like the chips do', (tester) async {
      // Bug (owner report, 2026-11-06): after a Calendar pick the row stayed
      // in strip mode, so `Add note` was unreachable — backdated entries
      // could not take a note in the same pass.
      await openSheet(tester);
      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Calendar…'), findsOneWidget);

      await tester.tap(find.text('Calendar…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Calendar…'), findsNothing); // strip collapsed
      expect(find.text('Add note'), findsOneWidget); // note reachable again
    });

    testWidgets('Add note swaps in a field, keeps the entry note', (
      tester,
    ) async {
      await openSheet(tester);
      await tester.tap(find.text('Add note'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'stationery');
      await press(tester, '3');
      await press(tester, '5');
      await tester.tap(find.text('Rent'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.note, 'stationery');
    });

    // Hardening #20: sheet routes stay hit-testable during the pop
    // animation — the second tap of a double-tap must not pop the host.
    testWidgets('double-tap Save pops exactly once, host survives', (
      tester,
    ) async {
      await openSheet(tester);
      await press(tester, '5');
      await tester.tap(find.text('Food'));
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump(); // exit animation begins; sheet still hittable
      await tester.tap(find.text('Save')); // the dangerous second tap
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<EntryKind>), findsNothing); // popped
      expect(result, isNotNull); // and only its own pop returned a value
      expect(find.text('open'), findsOneWidget); // host route survives
    });

    // Device feedback 2026-11-04: a large system font scale made the fixed
    // sheet budget overflow — pixel-overflow stripes and a Save button
    // half-hidden behind the system nav bar.
    testWidgets('large system font scale: no overflow, Save stays on screen', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0; // Android max
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showQuickAdd(
                    context,
                    categories: _cats,
                    currency: _usd,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // no RenderFlex overflow
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(save.bottom, lessThanOrEqualTo(600)); // test surface 800×600
      expect(save.top, greaterThanOrEqualTo(0));
      // Chips must not be cut by their row: at 2× fonts a FilterChip stands
      // ~64 dp tall — a fixed 40 dp row clips half the glyph (the overflow
      // stripes on the device screenshot).
      final row = tester.getRect(find.byKey(const Key('chip-row')));
      final chip = tester.getRect(find.byType(FilterChip).first);
      expect(chip.top, greaterThanOrEqualTo(row.top));
      expect(chip.bottom, lessThanOrEqualTo(row.bottom + 0.5));
    });
  });

  // Device feedback 2026-11-04 pm: a 3-button-nav device painted Save
  // under the system bar, and landscape clipped the pad mid-row. Both
  // hid in tests because the fake view carries zero insets and the old
  // surface (800×600) never rendered the landscape split on purpose.
  group('system insets (device 2026-11-04 pm)', () {
    void setPhoneView(WidgetTester tester, {required bool landscape}) {
      tester.view.physicalSize = landscape
          ? const Size(2520, 1080) // logical 840×360, like the device shot
          : const Size(1080, 2400); // logical 360×800
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('portrait + 48 dp nav bar: Save fully clears the bar', (
      tester,
    ) async {
      setPhoneView(tester, landscape: false);
      // A nav bar is view *padding*, not an inset — scroll-controlled
      // sheets get no automatic bottom SafeArea; the sheet must clear it.
      tester.view.viewPadding = const FakeViewPadding(bottom: 144); // 48 dp
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(save.bottom, lessThanOrEqualTo(800 - 48 + 0.5));
      expect(save.top, greaterThan(0));
    });

    testWidgets('landscape: whole pad renders, Save on screen', (tester) async {
      setPhoneView(tester, landscape: true);
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      // The 0 key anchors the pad's bottom row — mid-row clipping (the
      // device screenshot) left it outside the sheet.
      final zero = tester.getRect(find.byKey(const Key('keypad-0')));
      expect(zero.top, greaterThanOrEqualTo(0));
      expect(zero.bottom, lessThanOrEqualTo(360 + 0.5));
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      final rect = tester.getRect(save);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(360 + 0.5));
    });

    testWidgets('landscape at 2× font: no overflow, Save reachable', (
      tester,
    ) async {
      setPhoneView(tester, landscape: true);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      final rect = tester.getRect(save);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(360 + 0.5));
    });
  });

  group('draft restore + emit (ruling 2, owner 2026-11-11)', () {
    testWidgets('half-typed entry comes back and completes', (tester) async {
      await openSheet(
        tester,
        draft: QuickAddDraft(
          amount: '12.34',
          currencyCode: 'USD',
          kind: EntryKind.income,
          categoryId: 2,
          day: DateTime(2026, 11, 9),
          note: 'cafe',
        ),
      );
      expect(amountText(tester), '12.34');
      // The note stays active (it had content); kind+category restored —
      // the proof is the completed save.
      expect(find.text('cafe'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result!.amount.minorUnits, 1234);
      expect(result!.kind, EntryKind.income);
      expect(result!.categoryId, 2);
      expect(result!.note, 'cafe');
      expect(result!.day, DateTime(2026, 11, 9));
    });

    testWidgets('draft outranks the warm defaults', (tester) async {
      await openSheet(
        tester,
        initialKind: EntryKind.income,
        initialCategoryId: 2,
        draft: QuickAddDraft(
          amount: '5',
          currencyCode: 'USD',
          kind: EntryKind.expense,
          categoryId: 1,
          day: DateTime(2026, 11, 10),
        ),
      );
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result!.kind, EntryKind.expense);
      expect(result!.categoryId, 1);
    });

    testWidgets('every edit emits the current draft', (tester) async {
      final emitted = <QuickAddDraft>[];
      await openSheet(tester, onDraft: emitted.add);
      await press(tester, '7');
      await press(tester, '5');
      expect(emitted.last.amount, '75');
      await press(tester, 'back');
      await press(tester, 'back');
      expect(emitted.last.amount, '');
      // The last state before death is all a caller needs to persist.
      expect(emitted.last.currencyCode, 'USD');
    });

    testWidgets('damaged buffer cold-opens instead of lying', (tester) async {
      await openSheet(
        tester,
        draft: QuickAddDraft(
          amount: '1a.2.3',
          currencyCode: 'USD',
          kind: EntryKind.expense,
          categoryId: 1,
          day: DateTime(2026, 11, 10),
        ),
      );
      expect(amountText(tester), '0');
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });
  });
}
