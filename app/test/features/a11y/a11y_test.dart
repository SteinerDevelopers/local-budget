// #19 — the §5 accessibility bar, pinned as tests:
//  * rows are ONE merged TalkBack node ("Coffee, Lunch, −$12.40, Oct 29");
//  * day groups and EXPENSE/INCOME sections are header semantics;
//  * expense/income always differ by sign AND word, never color alone;
//  * system text scale up to 1.3× renders every screen without clipping —
//    only the QuickAdd hero shrink-wraps (FittedBox), everything else fits.
//
// drift rules are the ones #17/#18 learned: close() INSIDE the test body,
// ensureDefaults() when pumping LocalBudgetApp directly.
import 'dart:ffi' show DynamicLibrary;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/ledger/balance_strip.dart';
import 'package:local_budget/features/ledger/transaction_row.dart';
import 'package:local_budget/features/ledger/view_models.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

Money usd(int minor) => Money(minor, Currency.resolve('USD'));

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> pumpApp(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
  }

  // Plain get(), never watch…().first in a test body: cancelling a drift
  // query stream inside fakeAsync deadlocks the next write in this isolate.
  Future<int> categoryId(LedgerRepository r, {bool income = false}) async {
    final cats = await r.categories();
    return cats.firstWhere((c) => c.isIncome == income).id;
  }

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> openQuickAdd(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  Future<void> openManage(WidgetTester tester) async {
    await openQuickAdd(tester);
    await tester.dragUntilVisible(
      find.text('Manage'),
      find.byKey(const Key('chip-row')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Manage'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKeys(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      await tester.tap(find.byKey(Key('keypad-${k == '.' ? 'dot' : k}')));
    }
    await tester.pumpAndSettle();
  }

  group('§5 row semantics', () {
    testWidgets('expense row is ONE node: title, memo, signed amount, date', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          TransactionRow(
            tile: EntryTile(
              id: 1,
              icon: Icons.local_cafe_outlined,
              title: 'Coffee',
              memo: 'Lunch',
              amount: usd(1240),
              kind: EntryKind.expense,
              day: DateTime(2025, 5, 8), // Thu — a plain past day, not Today
            ),
          ),
        ),
      );

      // The §5 example format verbatim; children == [] proves the icon and
      // the texts did NOT leak as separate nodes.
      expect(
        tester.getSemantics(find.byType(TransactionRow)),
        matchesSemantics(
          label: 'Coffee, Lunch, \u2212\$12.40, Thu 8 May',
          isButton: true,
          children: <Matcher>[],
        ),
      );
      handle.dispose();
    });

    testWidgets('income row differs by sign AND word (never color alone)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          TransactionRow(
            tile: EntryTile(
              id: 2,
              icon: Icons.work_outline,
              title: 'Salary',
              amount: usd(240000),
              kind: EntryKind.income,
              day: DateTime(2025, 5, 9), // Fri
            ),
          ),
        ),
      );

      // '+' is spoken "plus" against the expense's "minus" — the meaning
      // lives in the label, so color blindness cannot lose it (§5).
      expect(
        tester.getSemantics(find.byType(TransactionRow)),
        matchesSemantics(
          label: 'Salary, +\$2,400.00, Fri 9 May',
          isButton: true,
          children: <Matcher>[],
        ),
      );
      handle.dispose();
    });

    testWidgets('balance stats merge into one node with their word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          BalanceStrip(
            summary: BalanceSummary(income: usd(240000), expenses: usd(9950)),
          ),
        ),
      );
      // Words INCOME / EXPENSES / NET ride along with the amounts.
      expect(
        tester.getSemantics(find.text('INCOME')),
        matchesSemantics(label: 'Income \$2,400.00', children: <Matcher>[]),
      );
      expect(
        tester.getSemantics(find.text('EXPENSES')),
        matchesSemantics(label: 'Expenses \$99.50', children: <Matcher>[]),
      );
      expect(
        tester.getSemantics(find.text('NET')),
        matchesSemantics(label: 'Net \$2,300.50', children: <Matcher>[]),
      );
      handle.dispose();
    });

    testWidgets('negative net speaks the minus sign with the Net word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          BalanceStrip(
            summary: BalanceSummary(income: usd(1000), expenses: usd(2543)),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('NET')),
        matchesSemantics(label: 'Net \u2212\$15.43', children: <Matcher>[]),
      );
      handle.dispose();
    });
  });

  group('§5 section & control semantics (full app)', () {
    testWidgets('day group header is announced as a header', (tester) async {
      final r = freshRepo();
      try {
        final handle = tester.ensureSemantics();
        await r.repo.ensureDefaults();
        await r.repo.addEntry(
          date: DateTime.now(),
          amount: usd(1240),
          isIncome: false,
          categoryId: await categoryId(r.repo),
          note: 'Oat flat white',
        );
        await pumpApp(tester, r.repo);

        expect(
          tester.getSemantics(find.text('Today')),
          isSemantics(label: 'Today', isHeader: true),
        );
        handle.dispose();
      } finally {
        await r.db.close();
      }
    });

    testWidgets('FAB, section headers and drag handles announce themselves', (
      tester,
    ) async {
      final r = freshRepo();
      try {
        final handle = tester.ensureSemantics();
        await r.repo.ensureDefaults();
        await pumpApp(tester, r.repo);

        // This SDK exposes Tooltip as a `tooltip:` semantics property on the
        // FAB node — TalkBack reads it exactly.
        expect(
          tester.getSemantics(find.byType(FloatingActionButton)),
          isSemantics(tooltip: 'Add transaction'),
        );

        await openManage(tester);
        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();

        // EXPENSE / INCOME are section headers (§5).
        expect(
          tester.getSemantics(find.text('EXPENSE')),
          isSemantics(label: 'EXPENSE', isHeader: true),
        );
        expect(
          tester.getSemantics(find.text('INCOME')),
          isSemantics(label: 'INCOME', isHeader: true),
        );
        // The drag handle's semanticLabel merges into the tile node with
        // the row label; ReorderableListView adds Move actions on top.
        expect(
          tester.getSemantics(find.byIcon(Icons.drag_handle).first),
          isSemantics(label: 'Food\nReorder EXPENSE category'),
        );
        handle.dispose();
      } finally {
        await r.db.close();
      }
    });

    testWidgets('QuickAdd hero is one node; selected chip says selected', (
      tester,
    ) async {
      final r = freshRepo();
      try {
        final handle = tester.ensureSemantics();
        await r.repo.ensureDefaults();
        await pumpApp(tester, r.repo);
        await openQuickAdd(tester);
        await tapKeys(tester, '12.40');

        // The hero merge: symbol + digits as one spoken label.
        expect(
          tester.getSemantics(find.byKey(const Key('amount-value'))),
          isSemantics(label: 'Amount 12.40'),
        );

        await tester.tap(find.widgetWithText(FilterChip, 'Food'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.text('Food')),
          isSemantics(label: 'Food', isSelected: true),
        );
        handle.dispose();
      } finally {
        await r.db.close();
      }
    });
  });

  group('§5 text scale to 1.3× — no clipping', () {
    // Phone viewport; 1.3× system text. Any RenderFlex overflow surfaces as
    // a test exception, so takeException()==null *is* the "no clipping" gate.
    Future<void> scaleUp(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('ledger at 360 dp / 1.3× renders without overflow', (
      tester,
    ) async {
      final r = freshRepo();
      try {
        await scaleUp(tester);
        await r.repo.ensureDefaults();
        await r.repo.addEntry(
          date: DateTime.now(),
          amount: usd(1240),
          isIncome: false,
          categoryId: await categoryId(r.repo),
          note: 'Whole foods run with a very long memo for the ellipsis',
        );
        await r.repo.addEntry(
          date: DateTime.now(),
          amount: usd(2400000),
          isIncome: true,
          categoryId: await categoryId(r.repo, income: true),
        );
        await pumpApp(tester, r.repo);
        expect(tester.takeException(), isNull);
      } finally {
        await r.db.close();
      }
    });

    testWidgets('QuickAdd hero shrink-wraps a 10-digit amount (FittedBox)', (
      tester,
    ) async {
      final r = freshRepo();
      try {
        await scaleUp(tester);
        await r.repo.ensureDefaults();
        await pumpApp(tester, r.repo);
        await openQuickAdd(tester);
        await tapKeys(tester, '1234567.89');

        // Without the FittedBox this Row overflows its 328 dp at 1.3× and
        // takeException() would carry the RenderFlex error.
        expect(tester.takeException(), isNull);
        expect(
          find.ancestor(
            of: find.byKey(const Key('amount-value')),
            matching: find.byType(FittedBox),
          ),
          findsOneWidget,
        );
      } finally {
        await r.db.close();
      }
    });

    testWidgets('Manage + category screens at 1.3×', (tester) async {
      final r = freshRepo();
      try {
        await scaleUp(tester);
        await r.repo.ensureDefaults();
        await pumpApp(tester, r.repo);
        await openManage(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The 4-wide icon grid takes the same scale without clipping.
        await tester.tap(find.byTooltip('Add expense category'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await r.db.close();
      }
    });
  });
}
