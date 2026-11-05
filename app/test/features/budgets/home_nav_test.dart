// Owner IA pass, 2026-11-05: Receipts / Budgets / Bills / Goals switch from
// a bottom bar on the home screen. These tests pin the contract the sheet
// tests can't see: the nav drives the embedded panel, the transaction FABs
// belong to Receipts only, and the Expenses stat is a panel switch now.
import 'dart:ffi' show DynamicLibrary;

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show LedgerScreen, monthIndexOf, monthTitle;
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final now = DateTime.now();
  final thisMonth = monthIndexOf(now);

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  /// Drift hands results back on the real event loop (same ceiling as
  /// reports_b4_test); one pump would leave the balance strip on its
  /// placeholder summary.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openHome(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LedgerScreen(repository: repo),
      ),
    );
    await settle(tester);
  }

  testWidgets('the bottom nav carries the four destinations', (tester) async {
    final (:db, :repo) = freshRepo();
    await openHome(tester, repo);
    for (final label in ['Receipts', 'Budgets', 'Bills', 'Goals']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Receipts is the ledger: the month rows and both add FABs are live.
    expect(find.byKey(const ValueKey('fab-quickadd')), findsOneWidget);
    expect(find.byKey(const ValueKey('fab-capture')), findsOneWidget);
    await db.close();
  });

  testWidgets('nav switches panels; FABs stay on Receipts', (tester) async {
    final (:db, :repo) = freshRepo();
    await openHome(tester, repo);

    await tester.tap(find.text('Bills'));
    await settle(tester);
    expect(find.text('No bills yet'), findsOneWidget);
    expect(find.byKey(const Key('home-tab-bills')), findsOneWidget);
    expect(find.byKey(const ValueKey('fab-quickadd')), findsNothing);

    await tester.tap(find.text('Goals'));
    await settle(tester);
    expect(find.byKey(const Key('home-tab-goals')), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);

    await tester.tap(find.text('Budgets'));
    await settle(tester);
    expect(find.byKey(const Key('home-budget-prev')), findsOneWidget);
    // The panel’s own month row follows the ledger's month.
    expect(find.text(monthTitle(thisMonth)), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-budget-next')));
    await settle(tester);
    expect(find.text(monthTitle(thisMonth + 1)), findsOneWidget);

    await tester.tap(find.text('Receipts'));
    await settle(tester);
    expect(find.byKey(const ValueKey('fab-quickadd')), findsOneWidget);
    expect(find.byKey(const Key('home-budget-prev')), findsNothing);
    await db.close();
  });

  testWidgets('the Expenses stat switches panels instead of opening a sheet', (
    tester,
  ) async {
    final (:db, :repo) = freshRepo();
    await openHome(tester, repo);
    // The strip renders its caps labels (design §2.1).
    await tester.tap(find.text('EXPENSES'));
    await settle(tester);
    expect(find.byKey(const Key('home-budget-prev')), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    await db.close();
  });
}
