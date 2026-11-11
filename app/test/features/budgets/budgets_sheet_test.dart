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

// #34 — the budgets sheet (design e3 §2.1/§2.2): opened from the ledger's
// Expenses stat and from Reports, overall target + category limits on the
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

    testWidgets('Bills ships live empty state; Goals still a slot (§2.1)', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-bills')), findsOneWidget);
      // #35 replaced the placeholder with the real (empty) Bills tab.
      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.byKey(const Key('bill-add-empty')), findsOneWidget);
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

  // 'Manage entry point (§2.4)' group removed 2026-11-06 with the duplicate
  // Manage → 'Budgets & bills' row (the bottom nav covers it; the sheet's
  // own tests above keep the Expenses-stat / Reports paths covered).

  group('Rollover switch & period surfacing (#38)', () {
    testWidgets('the switch persists device-wide and survives a reopen', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      await openSheet(tester, repo);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('rollover-switch')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('rollover-switch')));
      await settle(tester);
      expect(await repo.budgetRollover(), isTrue);
      // Dismiss on the scrim and reopen: the setting is device-wide state,
      // not sheet state (§2.1 — the footer mirrors the Settings key).
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('rollover-switch')))
            .value,
        isTrue,
      );
      await db.close();
    });

    testWidgets('weekly row sums its ISO week and shows the caption', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 3000,
        currencyCode: 'USD',
        periodType: 'weekly',
      );
      await spend(repo, catId: food, date: now, minor: 500); // in week
      // Any day 10 ahead is outside the ISO week by construction (weeks end
      // at most 6 days ahead); near a month end fall back 10 days back,
      // which always lands in an earlier week too.
      final ahead = now.add(const Duration(days: 10));
      final outside = ahead.month == now.month && ahead.year == now.year
          ? ahead
          : now.subtract(const Duration(days: 10));
      await spend(repo, catId: food, date: outside, minor: 700);
      await openSheet(tester, repo);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsNothing);
      expect(find.textContaining('\$5.00 / \$30.00'), findsOneWidget);
      await db.close();
    });

    testWidgets('non-monthly rows never carry, even with rollover on', (
      tester,
    ) async {
      // Regression: a yearMonth key cannot name a predecessor week, so a
      // weekly chain must not walk (§3.3 — progress rows, carry always 0).
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day - now.weekday + 1,
      );
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      final prevStart = weekStart.subtract(const Duration(days: 7));
      await repo.setBudgetRollover(true);
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(prevStart.year, prevStart.month)),
        limitMinor: 3000,
        currencyCode: 'USD',
        periodType: 'weekly',
      );
      await spend(
        repo,
        catId: food,
        date: weekStart.subtract(const Duration(days: 1)), // prev Sunday
        minor: 1000, // $10 of $30 → $20 carries
      );
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 3000,
        currencyCode: 'USD',
        periodType: 'weekly',
      );
      await spend(repo, catId: food, date: now, minor: 500);
      await openSheet(tester, repo);
      // Nominal limit and no carry badge anywhere (§3.3).
      expect(find.textContaining('\$5.00 / \$30.00'), findsOneWidget);
      expect(find.textContaining('from'), findsNothing);
      await db.close();
    });

    testWidgets('yearly row sums the calendar year with its caption', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      await repo.setBudget(
        categoryId: food,
        yearMonth: yearMonthOf(DateTime(now.year, now.month)),
        limitMinor: 10000,
        currencyCode: 'USD',
        periodType: 'yearly',
      );
      await spend(repo, catId: food, date: now, minor: 500);
      // January of the same year — different month, same yearly period.
      await spend(
        repo,
        catId: food,
        date: DateTime(now.year, 1, 15),
        minor: 700,
      );
      await openSheet(tester, repo);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.textContaining('\$12.00 / \$100.00'), findsOneWidget);
      await db.close();
    });
  });
}
