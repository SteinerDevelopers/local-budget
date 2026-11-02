// On-device smoke for the e2e-android stage: builds the APK, installs it on
// the headless emulator and drives the real #17 journey — file-backed SQLite
// (path_provider + sqlite3_flutter_libs), seeding, QuickAdd, strip.
// The emulator may carry app data from an earlier run, so nothing here
// asserts an empty starting state — only that this entry lands.
//
// Like host widget tests, the integration binding blocks the event loop
// between pumps, so database round-trips need tester.runAsync yields.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart';
import 'package:local_budget/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('boots on the current month and takes a manual entry', (
    tester,
  ) async {
    // Await the real async main to completion: file-backed DB open,
    // seeding and the notification bootstrap (#35) all happen before
    // runApp, and a fixed yield is not enough on a cold-booted emulator.
    await tester.runAsync(() => app.main());
    await settle(tester);

    final now = DateTime.now();
    expect(find.text(monthTitle(monthIndexOf(now))), findsOneWidget);

    // QuickAdd: 25.43 Food → save.
    await tester.tap(find.byKey(const ValueKey('fab-quickadd')));
    await settle(tester);
    for (final key in [
      'keypad-2',
      'keypad-5',
      'keypad-dot',
      'keypad-4',
      'keypad-3',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilterChip, 'Food'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.text('\u2212\$25.43'), findsWidgets); // row and/or strip
    expect(find.text('Food'), findsWidgets);

    // Extra frame through the real engine: the point is a green
    // build->install->drive->teardown loop on the emulator.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text(monthTitle(monthIndexOf(now))), findsOneWidget);

    // ---- E3 journey (#39): budget → bill → mark paid → home row. ----
    // The emulator image may carry data from earlier runs, so every step
    // tolerates leftovers: chips only list unbudgeted categories, and the
    // assertions look for presence, never counts.

    // Give the category we just spent in a monthly budget.
    await tester.tap(find.text('EXPENSES'));
    await settle(tester);
    final foodChip = find.descendant(
      of: find.byKey(const Key('chip-row')),
      matching: find.text('Food'),
    );
    if (foodChip.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('budget-add')));
      await settle(tester);
      await tester.tap(foodChip);
      await tester.pump();
      for (final d in ['1', '0', '0', '0']) {
        // $100.00 — keypad digits are major units with an implied dot.
        await tester.tap(find.byKey(Key('keypad-$d')));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('limit-save')));
      await tester.tap(find.byKey(const Key('limit-save')));
      await settle(tester);
    }
    // A progress row ('$X of $Y' style) is on screen either way.
    expect(find.textContaining(' / \$'), findsWidgets);

    // A bill due today, paid off through the detail sheet (§2.3).
    await tester.tap(find.text('Bills'));
    await settle(tester);
    if (find.text('E2E bill').evaluate().isEmpty) {
      final add = find.byKey(const Key('bill-add'));
      await tester.tap(
        add.evaluate().isNotEmpty
            ? add
            : find.byKey(const Key('bill-add-empty')),
      );
      await settle(tester);
      await tester.enterText(find.byKey(const Key('bill-name')), 'E2E bill');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bill-categories')),
          matching: find.text('Utilities'),
        ),
      );
      await tester.pump();
      for (final d in ['2', '0', '0', '0']) {
        // $20.00 — monthly default falls due today.
        await tester.tap(find.byKey(Key('keypad-$d')));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('bill-save')));
      await tester.tap(find.byKey(const Key('bill-save')));
      await settle(tester);
    }
    expect(find.text('E2E bill'), findsWidgets);

    // Open the detail and mark paid: a real ledger row is written and the
    // cursor advances (§3.4 — the pass is a hint, this tap is the record).
    await tester.tap(find.text('E2E bill').first);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('bill-mark-paid')));
    await tester.tap(find.byKey(const Key('bill-mark-paid')));
    await settle(tester);

    // Dismiss the sheet via the barrier gap above it — the paid bill must
    // now stand out on the home ledger as today's expense.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.textContaining('Bill: E2E bill'), findsWidgets);
    expect(find.text('\u2212\$20.00'), findsWidgets);
  });
}
