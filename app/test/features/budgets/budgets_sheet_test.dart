// #34 — the budgets sheet (design e3 §2.1/§2.2): opened from the ledger's
// Expenses stat and from Manage, overall target + category limits on the
// shared keypad, rollover badge, overspend honesty, copy-last-month.
//
// Same drift rules as manage_test.dart: close the db INSIDE the test body.
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/ledger/balance_strip.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf, monthTitle;
import 'package:local_budget/features/ledger/view_models.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final now = DateTime.now();
  final thisMonth = monthIndexOf(now);
  final prevDay = DateTime(now.year, now.month - 1, 5);

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> openSheet(
    WidgetTester tester,
    LedgerRepository repo, {
    int? monthIndex,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBudgetsSheet(
                context,
                repository: repo,
                monthIndex: monthIndex ?? thisMonth,
                currency: usd,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Seeds one spent amount in [date]'s month for [catId].
  Future<void> spend(
    LedgerRepository repo, {
    required int catId,
    required DateTime date,
    required int minor,
  }) async {
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: date,
      amount: Money(minor, usd),
      source: TransactionSource.manual,
      categoryId: catId,
    );
  }

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key('keypad-$key')));
    await tester.pump();
  }

  /// The save → pop → reload chain resolves in microtasks between frames;
  /// pump past the pop animation, then let the reload render.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    tester
        .widget<FilledButton>(find.byKey(const Key('limit-save')))
        .onPressed!();
    await settle(tester);
  }

  String amountText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('amount-value'))).data!;

  group('BalanceStrip wiring (§2.1)', () {
    testWidgets('the Expenses stat opens budgets; Income stays inert', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BalanceStrip(
              summary: BalanceSummary(
                income: Money(5000, usd),
                expenses: Money(1250, usd),
              ),
              onExpensesTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('EXPENSES'));
      await tester.pump();
      expect(taps, 1);
      await tester.tap(find.text('INCOME'));
      await tester.pump();
      expect(taps, 1, reason: 'only the Expenses stat is a button');
    });
  });

  group('Budgets sheet (§2.1)', () {
    testWidgets('cold month: empty state, no add button without categories', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      expect(find.text('No budgets yet'), findsOneWidget);
      expect(find.text('Set a monthly target'), findsOneWidget);
      expect(find.byKey(const Key('budget-add')), findsNothing);
      await db.close();
    });

    testWidgets('set the overall target via the keypad', (tester) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      await tester.tap(find.text('Set a monthly target'));
      await tester.pumpAndSettle();
      expect(find.text('Monthly target'), findsOneWidget);
      // No period picker on the overall target (§2.2).
      expect(find.text('Weekly'), findsNothing);
      // Keypad digits are MAJOR units: 1-2-0-0 is $1,200.00.
      for (final d in ['1', '2', '0', '0']) {
        await press(tester, d);
      }
      await save(tester);
      expect(find.text('Spent \$0.00 of \$1,200.00'), findsOneWidget);
      await db.close();
    });

    testWidgets('add a category budget from the chips row', (tester) async {
      final (:db, :repo) = freshRepo();
      await repo.addCategory('Food');
      await openSheet(tester, repo);
      await tester.tap(find.byKey(const Key('budget-add')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('chip-row')),
          matching: find.text('Food'),
        ),
      );
      await tester.pump();
      await press(tester, '5'); // $5.00 — one major-unit digit
      await save(tester);
      expect(find.textContaining('\$0.00 / \$5.00'), findsOneWidget);
      await db.close();
    });

    testWidgets('editing a row prefills the stored limit and saves', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 3000,
        currencyCode: 'USD',
      );
      await openSheet(tester, repo);
      expect(find.textContaining('\$0.00 / \$30.00'), findsOneWidget);
      await tester.tap(find.textContaining('\$0.00 / \$30.00'));
      await tester.pumpAndSettle();
      expect(amountText(tester), contains('30'));
      await press(tester, '9');
      expect(amountText(tester), contains('309'));
      await save(tester);
      expect(find.textContaining('\$0.00 / \$309.00'), findsOneWidget);
      await db.close();
    });

    testWidgets('delete removes the row', (tester) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 3000,
        currencyCode: 'USD',
      );
      await openSheet(tester, repo);
      await tester.tap(find.textContaining('\$0.00 / \$30.00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('limit-delete')));
      await settle(tester);
      expect(find.text('No budgets yet'), findsOneWidget);
      await db.close();
    });

    testWidgets('rollover badge adds last month’s carry', (tester) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudgetRollover(true);
      final prevYm = yearMonthOf(DateTime(prevDay.year, prevDay.month));
      await repo.setBudget(
        categoryId: food,
        yearMonth: prevYm,
        limitMinor: 30000,
        currencyCode: 'USD',
      );
      await spend(
        repo,
        catId: food,
        date: prevDay,
        minor: 10000, // $100 of $300 → $200 carries
      );
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 20000,
        currencyCode: 'USD',
      );
      await openSheet(tester, repo);
      expect(find.textContaining('+\$200.00 from'), findsOneWidget);
      // Effective limit is shown, so the bar and the number agree (§3.3).
      expect(find.textContaining('\$0.00 / \$400.00'), findsOneWidget);
      await db.close();
    });

    testWidgets('overspent: full bar and the truth number, no warning icon', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 500,
        currencyCode: 'USD',
      );
      await spend(repo, catId: food, date: now, minor: 700);
      await openSheet(tester, repo);
      expect(find.textContaining('\$7.00 / \$5.00'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await db.close();
    });

    testWidgets('Bills and Goals slots ship empty (§2.1)', (tester) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-bills')), findsOneWidget);
      expect(find.text('Bills are coming in this update'), findsOneWidget);
      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-goals')), findsOneWidget);
      await db.close();
    });

    testWidgets('copy last month is insert-only (§2.1)', (tester) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      final rent = await repo.addCategory('Rent');
      final prevYm = yearMonthOf(DateTime(prevDay.year, prevDay.month));
      await repo.setBudget(
        categoryId: food,
        yearMonth: prevYm,
        limitMinor: 500,
        currencyCode: 'USD',
      );
      await repo.setBudget(
        categoryId: rent,
        yearMonth: prevYm,
        limitMinor: 4000,
        currencyCode: 'USD',
      );
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 900,
        currencyCode: 'USD',
      );
      await openSheet(tester, repo);
      await tester.tap(find.byKey(const Key('budget-copy')));
      await settle(tester);
      // Rent copied; Food kept its own number.
      expect(find.textContaining('\$0.00 / \$40.00'), findsOneWidget);
      expect(find.textContaining('\$0.00 / \$9.00'), findsOneWidget);
      expect(find.textContaining('\$0.00 / \$5.00'), findsNothing);
      await db.close();
    });

    testWidgets('chevrons shift the month in place', (tester) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      await tester.tap(find.byKey(const Key('budget-next')));
      await tester.pumpAndSettle();
      expect(find.text(monthTitle(thisMonth + 1)), findsOneWidget);
      await tester.tap(find.byKey(const Key('budget-prev')));
      await tester.pumpAndSettle();
      expect(find.text(monthTitle(thisMonth)), findsOneWidget);
      await db.close();
    });
  });

  group('Manage entry point (§2.4)', () {
    testWidgets('Budgets & bills opens the same sheet', (tester) async {
      final (:db, :repo) = freshRepo();
      await tester.pumpWidget(LocalBudgetApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fab-quickadd')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Manage'),
        find.byKey(const Key('chip-row')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Budgets & bills'));
      await tester.pumpAndSettle();
      expect(find.text('No budgets yet'), findsOneWidget);
      await db.close();
    });
  });
}
