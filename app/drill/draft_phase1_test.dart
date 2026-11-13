// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// Soak drill, phase 1 (owner soak word 2026-11-11): drive QuickAdd to a
// half-typed state, let the debounced draft write land, announce
// DRAFT-READY — then idle until the HOST kills the process
// (`am force-stop`, the only honest process death — an in-process test
// cannot kill itself). The drive session dying on that kill is expected;
// the marker line, not the exit code, is the phase-1 verdict.
//
// Run through drive with the prebuilt kit and --keep-app-running
// (device law: teardown must not touch the app/DB; the kill under test
// is only ever am force-stop):
//   flutter drive --profile --flavor free --keep-app-running \
//     -d <serial> --use-application-binary kit-d1.apk \
//     --driver integration_test/driver.dart \
//     --target integration_test/draft_phase1_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_budget/main.dart' as app;

/// Focus and first frames after a launch (especially right after a kill)
/// run on the REAL clock the fake one cannot see; pointer injection is
/// real too. Tap only when the widget actually hit-tests — with the
/// miss-warning made fatal, so a miss retries in real time instead of
/// silently tapping air. A drill that taps nothing is worse than one
/// that fails (bench lesson 2026-11-11, first smoke round).
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

  testWidgets('type a draft and hold the door for the kill', (tester) async {
    await tester.runAsync(() => app.main());
    // Cold start needs real wall-clock room (~5 s to first interaction
    // on this panel); fake settling outruns it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();
    await _tapHittable(tester, find.byKey(const ValueKey('receipt-add')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    // Draft-clear watchdog: the PREVIOUS cycle's save must have left a
    // cold pad here. Reading it on this (reliable, first) open catches a
    // clear failure one cycle later without racing a second open — a
    // DRAFT-LEAK line in the soak log names the offender loudly.
    final inherited =
        tester.widget<Text>(find.byKey(const Key('amount-value'))).data;
    if (inherited != '0') {
      debugPrint('DRAFT-LEAK previous cycle left amount=$inherited');
    }
    // Enter idempotently: erase whatever a failed earlier cycle left
    // (backspace on an empty pad is a no-op), then type the canonical
    // amount. "42.5" — four keys, the typed-entry shape the jank probe
    // established, plus a category so the draft carries a selection.
    for (var i = 0; i < 12; i++) {
      await _tapHittable(tester, find.byKey(const Key('keypad-back')));
      await tester.pump();
    }
    for (final k in ['keypad-4', 'keypad-2', 'keypad-dot', 'keypad-5']) {
      await _tapHittable(tester, find.byKey(Key(k)));
      await tester.pump();
    }
    final food = find.widgetWithText(FilterChip, 'Food');
    await tester.ensureVisible(food);
    await _tapHittable(tester, food);
    await tester.pump();
    // Two clocks, two waits (bench lesson 2026-11-11): the debounce
    // Timer lives in the FAKE clock (explicit pump fires it); the drift
    // write it starts is REAL I/O (real time lets it land). Production
    // runs one real clock and needs neither dance.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1000)),
    );
    debugPrint('DRAFT-READY amount=42.5 category=Food');
    // Hold: the host greps the marker, force-stops, and this loop dies
    // with the process. 120 s ceiling so a missed kill cannot hang the
    // soak forever.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
