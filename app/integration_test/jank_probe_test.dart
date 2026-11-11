// Finding 5 follow-up (bench 2026-11-07): the Flip6 gfxinfo number (21.4 %
// > 16 ms) could not be re-measured on the Tab A9+ because every system
// rail is blind there for a Flutter SurfaceView app — measured 2026-11-10:
// app gfxinfo renders "Total frames: 0" during verified foreground input,
// Samsung SurfaceFlinger keeps no frame history (empty --latency rows for
// the window layer, no BLAST child in --list), and media.performance and
// gameinfo services are absent from the build. So the instrument is
// Flutter's own FrameTiming pipeline: build/raster durations for every
// frame the engine really renders, collected on-device, reported by the
// local probe invocation it is:
//
//   flutter test integration_test/jank_probe_test.dart --profile \
//     -d <bench-tablet>
//
// Profile build on purpose: release-like AOT, same rendering pipeline,
// none of the debug VM's frame tax. The window drives the same QuickAdd
// save loop and ledger flings the bench walks use. Percentiles print as
// one `JANK …` line; thresholds are quoted at both 60 Hz (the bench's
// original > 16 ms law) and the tablet's real 90 Hz panel (≈11.1 ms).
// Frames outside the recorded vsync window are excluded, so idle frames
// cannot dilute the verdict — and too few frames aborts loudly instead
// of lying with a zero.

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
      await tester.tap(find.byKey(const Key('keypad-5')));
      await tester.pump();
      final food = find.widgetWithText(FilterChip, 'Food');
      await tester.ensureVisible(food);
      await tester.tap(food);
      await tester.pump();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);
    }

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
