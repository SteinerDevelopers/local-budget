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

// #37 — the Goals tab at the widget level (design e3 §2.4): empty state,
// the editor (blank target = open-ended, Value-clears on edit), detail
// with deposit/withdraw keypad sheets, and the transfer list. §3.5's
// exclusion is repository behavior — proven by goals_read_test.dart on
// the data side, so these tests focus on the flows.
//
// Same drift rules as bills_tab_test.dart: close the db INSIDE the body.
import 'dart:ffi' show DynamicLibrary;

import 'package:core/core.dart' show Currency, Money;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf;
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final thisMonth = monthIndexOf(DateTime.now());

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  /// Keypad digits are MAJOR units: `tap 4, 5` = $45.00 = 4500 minor.
  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tapKey(tester, Key('keypad-$d'));
    }
  }

  Future<void> openGoalsTab(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBudgetsSheet(
                context,
                repository: repo,
                monthIndex: thisMonth,
                currency: usd,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('Goals'));
    await settle(tester);
  }

  Future<int> seedGoal(
    LedgerRepository repo, {
    String name = 'Camera',
    int? targetMinor = 5000,
    String? note,
  }) => repo.addGoal(
    name: name,
    currencyCode: 'USD',
    targetMinor: targetMinor,
    note: note,
  );

  Future<void> seedTransfer(
    LedgerRepository repo,
    int goalId, {
    int minor = 1000,
    bool withdraw = false,
  }) async => repo.addGoalTransfer(
    accountId: (await repo.defaultAccount()).id,
    goalId: goalId,
    date: DateTime.now(),
    amount: Money(minor, usd),
    isIncome: withdraw,
  );

  testWidgets('empty state creates a goal: name + keypad target round-trip', (
    tester,
  ) async {
    final (:repo, :db) = freshRepo();
    await openGoalsTab(tester, repo);
    expect(find.byKey(const Key('tab-goals')), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);

    await tapKey(tester, const Key('goal-add-empty'));
    expect(find.byKey(const Key('goal-name')), findsOneWidget);
    // The save button refuses an empty name.
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('goal-save'))).onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('goal-name')), 'Camera fund');
    await settle(tester);
    await typeAmount(tester, '45'); // $45 → 4500 minor
    await tapKey(tester, const Key('goal-save'));

    final goals = await repo.goals();
    expect(goals, hasLength(1));
    expect(goals.single.name, 'Camera fund');
    expect(goals.single.targetMinor, 4500);
    expect(goals.single.note, isNull);
    // The tab caught the reload without reopening.
    expect(find.text('No goals yet'), findsNothing);
    expect(find.byKey(Key('goal-row-${goals.single.id}')), findsOneWidget);
    await db.close();
  });

  testWidgets('deposit through the keypad sheet lands on the row and bar', (
    tester,
  ) async {
    final (:repo, :db) = freshRepo();
    final goalId = await seedGoal(repo, targetMinor: 5000); // $50
    await openGoalsTab(tester, repo);

    await tapKey(tester, Key('goal-row-$goalId'));
    expect(find.text('Add to goal'), findsOneWidget);
    expect(
      find.text('No transfers yet — add the first one below.'),
      findsOneWidget,
    );

    await tapKey(tester, const Key('goal-deposit'));
    await typeAmount(tester, '25'); // $25
    await tapKey(tester, const Key('goal-amount-confirm'));

    // Detail updates in place: +$25 row, 50 % progress.
    expect(find.text('+\$25.00'), findsOneWidget);
    expect(find.text('50% saved'), findsOneWidget);

    // Dismiss the detail via its scrim (top strip above the 72 % sheet);
    // the row and its bar catch up.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('\$25.00 / \$50.00'), findsOneWidget);
    await db.close();
  });

  testWidgets('withdraw reverses the total; disabled at zero', (tester) async {
    final (:repo, :db) = freshRepo();
    final goalId = await seedGoal(repo, targetMinor: 5000);
    await seedTransfer(repo, goalId, minor: 1000); // +$10
    await openGoalsTab(tester, repo);
    await tapKey(tester, Key('goal-row-$goalId'));

    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('+\$10.00'), findsOneWidget);

    await tapKey(tester, const Key('goal-withdraw'));
    await typeAmount(tester, '4');
    await tapKey(tester, const Key('goal-amount-confirm'));
    expect(find.text('−\$4.00'), findsOneWidget); // U+2212 minus
    expect(find.text('Deposit'), findsOneWidget); // still there
    expect(find.text('\$6.00 / \$50.00'), findsOneWidget); // detail header
    await db.close();
  });

  testWidgets('withdraw is inert when nothing is saved', (tester) async {
    final (:repo, :db) = freshRepo();
    final goalId = await seedGoal(repo);
    await openGoalsTab(tester, repo);
    await tapKey(tester, Key('goal-row-$goalId'));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('goal-withdraw')))
          .onPressed,
      isNull,
    );
    await db.close();
  });

  testWidgets('edit rename + cleared target makes the goal open-ended', (
    tester,
  ) async {
    final (:repo, :db) = freshRepo();
    final goalId = await seedGoal(repo, targetMinor: 5000, note: '35mm first');
    await openGoalsTab(tester, repo);
    await tapKey(tester, Key('goal-row-$goalId'));

    await tapKey(tester, const Key('goal-edit'));
    expect(find.text('Edit goal'), findsOneWidget);
    expect(find.text('35mm first'), findsOneWidget); // note prefilled

    await tester.enterText(find.byKey(const Key('goal-name')), 'Film fund');
    // Wipe the pre-filled target: 6 backspaces over "50".
    for (var i = 0; i < 6; i++) {
      await tapKey(tester, const Key('keypad-back'));
    }
    await tapKey(tester, const Key('goal-save'));

    final goal = (await repo.goals()).single;
    expect(goal.name, 'Film fund');
    expect(goal.targetMinor, isNull); // Value(null) really cleared it
    expect(goal.note, '35mm first');
    // Open-ended rows show a bare total — no '/ target', no bar (§2.4).
    expect(find.textContaining('/ \$'), findsNothing);
    await db.close();
  });

  testWidgets('transfer rows stay invisible to budgets and the ledger feed', (
    tester,
  ) async {
    final (:repo, :db) = freshRepo();
    await repo.ensureDefaults();
    final goalId = await seedGoal(repo, targetMinor: 5000);
    await seedTransfer(repo, goalId, minor: 2500);
    // The repository guarantees the exclusion (data/goals_read_test); here
    // the tab must agree with the repository about the goal's own totals.
    await openGoalsTab(tester, repo);
    expect(find.text('\$25.00 / \$50.00'), findsOneWidget);
    final rows = await repo.transactionsInRange(
      epochDayOf(DateTime.now()) - 2,
      epochDayOf(DateTime.now()) + 2,
    );
    expect(rows.where((t) => t.goalId != null), isEmpty);
    await db.close();
  });
}
