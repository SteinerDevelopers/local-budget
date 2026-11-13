import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/scanner_consent.dart';

/// #56 — the one-time scanner consent gate. These three behaviours ARE the
/// ruling: ask once, honour the remembered answer silently, and treat "no
/// answer" as decline (no download without a yes).
class _FakeIntake implements CaptureIntake {
  @override
  bool allowScanner = true;

  @override
  bool get hasScreenshotRow => false;

  @override
  Future<CapturePick?> pick(CaptureChoice choice) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnsupportedError('unused');
}

void main() {
  late _FakeIntake intake;
  late String? stored;
  late List<String> writes;

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => gateScannerConsent(
              context,
              intake,
              read: () async => stored,
              write: (v) async {
                writes.add(v);
              },
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    intake = _FakeIntake();
    stored = null;
    writes = [];
  });

  testWidgets('first use asks, Fast scan allows and persists', (tester) async {
    await pumpGate(tester);
    expect(find.text('Fast scanning uses Google\u2019s scanner'), findsOne);
    // Owner copy law: the decline rung names its real capability.
    expect(find.textContaining('still reads the text on your device'), findsOne);
    await tester.tap(find.byKey(const Key('scanner-consent-fast')));
    await tester.pumpAndSettle();
    expect(intake.allowScanner, isTrue);
    expect(writes, ['fast']);
  });

  testWidgets('Take photo declines the module, camera stays usable', (
    tester,
  ) async {
    await pumpGate(tester);
    await tester.tap(find.byKey(const Key('scanner-consent-photo')));
    await tester.pumpAndSettle();
    expect(intake.allowScanner, isFalse);
    expect(writes, ['photo']);
  });

  testWidgets('remembered answer is honoured with no dialog', (tester) async {
    stored = 'photo';
    await pumpGate(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(intake.allowScanner, isFalse);
    expect(writes, isEmpty); // remembered: nothing re-persisted
    // …and the fast memory works symmetrically: it must override a stale
    // false without ever asking again.
    stored = 'fast';
    intake.allowScanner = false;
    await pumpGate(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(intake.allowScanner, isTrue);
    expect(writes, isEmpty);
  });

  testWidgets('no answer at all is a decline', (tester) async {
    await pumpGate(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    // System back: the route pops with no explicit choice.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(writes, ['photo']); // decided, not silence — and it is "no"
    expect(intake.allowScanner, isFalse);
  });
}
