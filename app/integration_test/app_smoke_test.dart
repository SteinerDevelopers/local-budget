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
  });
}
