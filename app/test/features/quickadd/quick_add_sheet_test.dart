import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/view_models.dart';
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
}
