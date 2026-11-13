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

// Finding 5 follow-up (bench 2026-11-07): the Flip6 gfxinfo number (21.4 %
// > 16 ms) could not be re-measured on the Tab A9+ because every system
// rail is blind there for a Flutter SurfaceView app — measured 2026-11-10:
// app gfxinfo renders "Total frames: 0" during verified foreground input,
// Samsung SurfaceFlinger keeps no frame history (empty --latency rows for
// the window layer, no BLAST child in --list), and media.performance and
// gameinfo services are absent from the build. So the instrument is
// Flutter's own FrameTiming pipeline: build/raster durations for every
// frame the engine really renders, collected on-device. Run it with:
//
//   flutter drive --profile --flavor free -d <bench-tablet> \
//     --driver integration_test/driver.dart \
//     --target integration_test/jank_probe_test.dart
//
// (`flutter drive`, not `flutter test`: this SDK's `flutter test` has no
// --profile flag -- measured 2026-11-10, the first run failed on it.)
//
// Profile build on purpose: release-like AOT, same rendering pipeline,
// none of the debug VM's frame tax. The window drives eight QuickAdd
// saves with a TYPED amount (12.49 — five keystrokes; a one-key window
// proved unable to exercise keystroke cost at all, 2026-11-10) and
// twelve ledger flings. Percentiles print as one `JANK …` line plus
// `JANK-SHEET`/`JANK-FLING` phase lines that localize the tail;
// thresholds are quoted at both 60 Hz (the bench's original > 16 ms
// law) and the tablet's real 90 Hz panel (≈11.1 ms).
// Launch frames are drained before the window opens (FrameTiming's epoch
// is monotonic, not DateTime-aligned, so the window is the collector
// queue, not a wall-clock slice) — and too few frames aborts loudly
// instead of lying with a zero.

import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_budget/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('frame timing under the bench interaction window', (
    tester,
  ) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => timings.addAll(batch);
    WidgetsBinding.instance.addTimingsCallback(collect);

    await tester.runAsync(() => app.main());
    await _settle(tester);

    // Startup frames below the interaction window would dilute percentiles
    // downward, so the collector only starts counting once the app has
    // settled and the queue is drained of launch frames.
    await _settle(tester);
    timings.clear();

    // Eight full QuickAdd saves — sheet animation, keypad, stream rebuild.
    for (var i = 0; i < 8; i++) {
      final add = find.byKey(const ValueKey('receipt-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _settle(tester);
      // Realistic entry: "12.49" — five keystrokes, the way a typed
      // amount actually arrives (bench 2026-11-10, after the single-
      // digit window proved unable to exercise keystroke cost at all).
      for (final k in [
        'keypad-1',
        'keypad-2',
        'keypad-dot',
        'keypad-4',
        'keypad-9',
      ]) {
        await tester.tap(find.byKey(Key(k)));
        await tester.pump();
      }
      final food = find.widgetWithText(FilterChip, 'Food');
      await tester.ensureVisible(food);
      await tester.tap(food);
      await tester.pump();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);
    }

    final sheetMark = timings.length;

    // Twelve ledger flings — list build cost at real velocity.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 6; i++) {
      await tester.fling(list, const Offset(0, -420), 2600);
      await _settle(tester);
      await tester.fling(list, const Offset(0, 420), 2600);
      await _settle(tester);
    }
    // Let the last timing reports land before closing the window.
    await _settle(tester);
    WidgetsBinding.instance.removeTimingsCallback(collect);

    final total = timings
        .map((t) => t.buildDuration + t.rasterDuration)
        .toList()
      ..sort();
    if (total.length < 20) {
      debugPrint('JANK ABORT: only ${total.length} frames in window — the '
          'probe drove no real frames; treat as void, never as zero.');
      return;
    }
    // Local phase split (this run only): where does the tail live?
    List<Duration> slice(int from, int to) => [
          for (final t in timings.sublist(
            from.clamp(0, timings.length),
            to.clamp(0, timings.length),
          ))
            t.buildDuration + t.rasterDuration,
        ]..sort();
    for (final (name, a, b) in [
      ('SHEET', 0, sheetMark),
      ('FLING', sheetMark, timings.length),
    ]) {
      final v = slice(a, b);
      if (v.length > 4) {
        debugPrint('JANK-$name frames=${v.length} '
            'p90=${v[(v.length * 0.9).floor().clamp(0, v.length - 1)].inMilliseconds}ms '
            'p99=${v[(v.length * 0.99).floor().clamp(0, v.length - 1)].inMilliseconds}ms '
            'over16_7=${v.where((d) => d > const Duration(milliseconds: 17)).length}');
      }
    }
    Duration at(double q) =>
        total[(total.length * q).floor().clamp(0, total.length - 1)];
    int over(Duration budget) => total.where((d) => d > budget).length;
    const law60 = Duration(milliseconds: 17);
    const panel90 = Duration(milliseconds: 12);
    debugPrint(
      'JANK frames=${total.length} '
      'p50=${at(0.5).inMilliseconds}ms p90=${at(0.9).inMilliseconds}ms '
      'p99=${at(0.99).inMilliseconds}ms max=${total.last.inMilliseconds}ms '
      'over16_7=${over(law60)} '
      '(${(100 * over(law60) / total.length).toStringAsFixed(1)}%) '
      'over11_1=${over(panel90)} '
      '(${(100 * over(panel90) / total.length).toStringAsFixed(1)}%)',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}
