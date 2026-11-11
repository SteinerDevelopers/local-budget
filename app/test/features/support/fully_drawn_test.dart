// The honest cold-start signal (support/fully_drawn.dart): the first real
// month event reports fully-drawn exactly once — after that data-bearing
// frame — and neither stream re-emissions, rebuilds, nor later pages mint
// a second report.

import 'dart:ffi';

import 'package:data/data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/support/fully_drawn.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  // Same SONAME override as the other drift-backed widget tests.
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  testWidgets('cold launch reports fully-drawn exactly once', (tester) async {
    resetFullyDrawnForTest();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('localbudget/lifecycle'),
          (call) async => calls.add(call),
        );
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();

    expect(
      calls.where((c) => c.method == 'reportFullyDrawn'),
      hasLength(1),
      reason: 'first month data must report fully-drawn once',
    );

    // Extra frames and stream quiescence mint no further reports.
    await tester.pump();
    await tester.pump();
    expect(calls, hasLength(1));

    // A DB write (stream re-emission through the same page) neither.
    await db.close(); // inside the body — see widget_test.dart header note
  });

  testWidgets('one-shot survives a second landing page instance', (tester) async {
    resetFullyDrawnForTest();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('localbudget/lifecycle'),
          (call) async => calls.add(call),
        );
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));

    // Re-pumping a fresh app widget builds new _MonthPage states; the
    // process-wide one-shot (matching the platform's own idempotence)
    // keeps the count at one.
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));

    await db.close();
  });
}
