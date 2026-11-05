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

    // QuickAdd: 25.43 Food → save. The sheet now keeps its content above
    // the AVD's nav bar (pipeline 146: that inset pushed the keypad's last
    // row under the clip edge and a raw tap fell through to the ledger),
    // so the driver scrolls before each tap — as a thumb does.
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await settle(tester);
    for (final key in [
      'keypad-2',
      'keypad-5',
      'keypad-dot',
      'keypad-4',
      'keypad-3',
    ]) {
      final keyFinder = find.byKey(Key(key));
      await tester.ensureVisible(keyFinder);
      await tester.pumpAndSettle();
      await tester.tap(keyFinder);
      await tester.pump();
    }
    final food = find.widgetWithText(FilterChip, 'Food');
    await tester.ensureVisible(food);
    await tester.pumpAndSettle();
    await tester.tap(food);
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
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

    // Give the category we just spent in a monthly budget. The add button
    // AND the chip row live inside the editor sheet, and a fresh emulator
    // image has zero budgets — so open first, then look (the old order
    // evaluated chips against the list, skipped the branch on clean
    // images, and left no progress row behind).
    await tester.tap(find.text('EXPENSES'));
    await settle(tester);
    final budgetAdd = find.byKey(const Key('budget-add'));
    if (budgetAdd.evaluate().isNotEmpty) {
      await tester.tap(budgetAdd);
      await settle(tester);
      final foodChip = find.descendant(
        of: find.byKey(const Key('chip-row')),
        matching: find.widgetWithText(FilterChip, 'Food'),
      );
      if (foodChip.evaluate().isNotEmpty) {
        // On the phone-sized viewport the chip row sits below the sheet's
        // clip edge — tapping the Text's centre hit a clipped neighbour
        // (pipeline 62 warning), so select the whole FilterChip: its centre
        // is always inside its own ink area once scrolled into view.
        await tester.ensureVisible(foodChip);
        await tester.pumpAndSettle();
        await tester.tap(foodChip);
        await tester.pump();
        for (final d in ['1', '0', '0', '0']) {
          // $1,000.00 — keypad digits are MAJOR units (1200 → 120000).
          await tester.tap(find.byKey(Key('keypad-$d')));
          await tester.pump();
        }
        await tester.ensureVisible(find.byKey(const Key('limit-save')));
        await tester.tap(find.byKey(const Key('limit-save')));
        await settle(tester);
      } else {
        // Leftover image where Food was budgeted in an earlier run.
        await tester.pageBack();
        await settle(tester);
      }
    }
    // A progress row ('$spent / $limit') is on screen either way.
    expect(find.textContaining(' / \$'), findsWidgets);

    // A bill due TODAY, paid off through the detail sheet (§2.3). The name
    // is unique per run: the emulator image persists data across pipelines,
    // and a leftover already-paid rule's cursor sits in a future month — its
    // detail would no longer offer `Mark paid` (pipeline 62 post-mortem).
    final billName = 'E2E ${DateTime.now().millisecondsSinceEpoch}';
    await tester.tap(find.text('Bills'));
    await settle(tester);
    final add = find.byKey(const Key('bill-add'));
    await tester.tap(
      add.evaluate().isNotEmpty ? add : find.byKey(const Key('bill-add-empty')),
    );
    await settle(tester);
    await tester.enterText(find.byKey(const Key('bill-name')), billName);
    // Defocus: the soft keyboard shrinks the viewport and moved sheet
    // content out from under the finder (pipeline 61 — the Utilities tap
    // hit a modal barrier at stale geometry). Unfocus, do NOT tap the
    // barrier: that would dismiss the sheet mid-form.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    final utilChip = find.descendant(
      of: find.byKey(const Key('bill-categories')),
      matching: find.widgetWithText(FilterChip, 'Utilities'),
    );
    await tester.ensureVisible(utilChip);
    await tester.pumpAndSettle();
    await tester.tap(utilChip);
    await tester.pump();
    for (final k in ['2', '0', 'dot', '0', '0']) {
      // $20.00 — digits are MAJOR units with an explicit dot (pipeline 62:
      // '2000' meant $2,000.00, so the home row never read '−$20.00').
      await tester.tap(find.byKey(Key('keypad-$k')));
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('bill-save')));
    await tester.tap(find.byKey(const Key('bill-save')));
    await settle(tester);
    expect(find.text(billName), findsWidgets);

    // Open the detail and mark paid: a real ledger row is written and the
    // cursor advances (§3.4 — the pass is a hint, this tap is the record).
    await tester.tap(find.text(billName).first);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('bill-mark-paid')));
    await tester.tap(find.byKey(const Key('bill-mark-paid')));
    await settle(tester);

    // Dismiss the sheet via the barrier gap above it, then walk the home
    // bar back to Receipts — since the 2026-11-05 IA pass the ledger is a
    // destination, not the surface a dismissed sheet revealed. The paid
    // bill must stand out there as today's expense.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await tester.tap(find.text('Receipts'));
    await settle(tester);
    expect(find.textContaining('Bill: $billName'), findsWidgets);
    expect(find.text('−\$20.00'), findsWidgets);

    // E4 #5: the header icon opens Reports on the live month — the KPI
    // strip and donut are computed from what this very journey wrote,
    // and the Year segment renders the same ledger at twelve-month scope.
    await tester.tap(find.byKey(const Key('reports-open')));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Reports'), findsOne);
    expect(find.byKey(const Key('kpi-spent')), findsOne);
    expect(find.byKey(const Key('donut-total')), findsOne);
    await tester.tap(find.text('Year'));
    await settle(tester);
    expect(find.textContaining(' avg'), findsOne);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('EXPENSES'), findsWidgets);

    // E8 #9 leg: Help opens from the home header, the search behaves
    // like the host-tested index on a real keyboard (half-typed word
    // lands), an article reads, and Reports carries its own entrance.
    await tester.tap(find.byKey(const Key('help-open')));
    await settle(tester);
    expect(find.text('Search help'), findsOne);
    await tester.enterText(find.byType(TextField), 'passphras');
    await settle(tester);
    expect(find.text('Backup and restore'), findsOne);
    await tester.tap(find.text('Backup and restore'));
    await settle(tester);
    expect(find.textContaining('passphrase'), findsWidgets);
    await tester.pageBack(); // article → list
    await settle(tester);
    await tester.pageBack(); // list → home
    await settle(tester);
    await tester.tap(find.byKey(const Key('reports-open')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('reports-help')));
    await settle(tester);
    expect(find.text('Scanning receipts'), findsOne);
  });
}
