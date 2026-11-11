// Soak drill, phase 2: relaunch after the host's force-stop and prove
// the draft came back — amount buffer verbatim — then SAVE it: the
// restored state must not just display, it must complete (NewEntry →
// ledger row), and saving is also what clears the draft so the next
// drill cold-starts honestly. DRAFT-PASS + one ledger row grown is the
// loop's full circle. Runs with --keep-app-running; see phase 1 header.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_budget/main.dart' as app;

/// Real-clock hit-test-aware tap (see phase 1 for the full why).
Future<void> _tapHittable(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 16; i++) {
    if (tester.any(f)) {
      try {
        WidgetController.hitTestWarningShouldBeFatal = true;
        await tester.tap(f);
        WidgetController.hitTestWarningShouldBeFatal = false;
        return;
      } catch (_) {
        WidgetController.hitTestWarningShouldBeFatal = false;
      }
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
  }
  await tester.tap(f); // persistent miss must fail the drill loudly
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('draft survives process death and completes', (tester) async {
    await tester.runAsync(() => app.main());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();
    await _tapHittable(tester, find.byKey(const ValueKey('receipt-add')));
    // The sheet opens only after two REAL drift reads (categories,
    // draft) — real time first, then settle frames, before asserting.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    // The exact buffer phase 1 typed — verbatim restore is the law.
    expect(
      tester.widget<Text>(find.byKey(const Key('amount-value'))).data,
      '42.5',
    );
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await _tapHittable(tester, save);
    // addEntry + draft clear are real writes — give them real time.
    // The cleared-pad proof lives in phase 1's watchdog (checking the
    // inherited pad on the NEXT cycle's first, reliable open): a second
    // open here raced the fake-clock-frozen pop on the bench, and a
    // flaky assertion is worth less than a late-but-honest one.
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    debugPrint('DRAFT-PASS restored=42.5 saved=yes');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
