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

// E4 B3 — the Reports month screen (spec §2.1): KPI strip, month stepper,
// category donut with a drill sheet, top merchants. Aggregates themselves
// are unit-tested in packages/budget; these tests pin the wiring and the
// screen's own rules (future is not navigable, past months show the
// per-day tile, exclusion rules reach the tiles).
//
// Same drift rules as budgets_sheet_test.dart: in-memory db, closed inside
// the test body.
import 'dart:ffi';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf, monthTitle;
import 'package:local_budget/features/reports/reports_screen.dart';
import 'package:local_budget/features/reports/reports_service.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5);
  final prevMonth = DateTime(now.year, now.month - 1, 15);
  final prevDays = DateTime(now.year, now.month, 0).day;

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> spend(
    LedgerRepository repo, {
    required int catId,
    required DateTime date,
    required int minor,
    String? merchant,
    bool isIncome = false,
  }) async {
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: date,
      amount: Money(minor, usd),
      source: TransactionSource.manual,
      categoryId: catId,
      merchant: merchant,
      isIncome: isIncome,
    );
  }

  /// Drift delivers on the real event loop; a lone `pumpAndSettle` can
  /// return while a drill-down's future is still pending under CPU load
  /// (parallel test files). Pump a ceiling so every awaiting chain flushes.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpReports(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReportsScreen(repository: repo),
      ),
    );
    await settle(tester);
  }

  /// Value text inside one KPI tile.
  Finder kpiValue(String key, String text) =>
      find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

  testWidgets('KPI strip counts engine-scope spend, income and net', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    final pay = await repo.addCategory('Pay', isIncome: true);
    await spend(repo, catId: food, date: thisMonth, minor: 12000);
    await spend(repo, catId: food, date: thisMonth, minor: 8000);
    await spend(
      repo,
      catId: pay,
      date: thisMonth,
      minor: 30000,
      isIncome: true,
    );
    await pumpReports(tester, repo);

    // Income never feeds Spent; Net = income − spend (§2.1).
    expect(kpiValue('kpi-spent', Money(20000, usd).format()), findsOne);
    expect(kpiValue('kpi-income', Money(30000, usd).format()), findsOne);
    expect(kpiValue('kpi-net', Money(10000, usd).format()), findsOne);
    // Current month → run-rate tile, never the per-day tile (§2.1).
    expect(find.byKey(Key('kpi-pacing')), findsOne);
    expect(find.byKey(Key('kpi-daily-avg')), findsNothing);
    expect(find.text('On pace for'), findsOne);

    await db.close();
  });

  testWidgets('donut shows the month total and drills into a category', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    final rent = await repo.addCategory('Rent');
    await spend(repo, catId: food, date: thisMonth, minor: 12000);
    await spend(repo, catId: rent, date: thisMonth, minor: 8000);
    await spend(
      repo,
      catId: food,
      date: thisMonth,
      minor: 500,
      merchant: 'Food Co',
    );
    await pumpReports(tester, repo);

    // The key sits on the center Text itself, so read its data.
    expect(
      tester.widget<Text>(find.byKey(Key('donut-total'))).data,
      Money(20500, usd).format(),
    );

    // Tap inside the ring, just clockwise of 12 o'clock — that point is in
    // the first (largest, Food) slice for sure; the ring spans radii
    // 52..104 around the chart center.
    final center = tester.getCenter(find.byType(PieChart));
    final r = 78.0;
    await tester.tapAt(center + Offset(r * math.sin(0.2), -r * math.cos(0.2)));
    await settle(tester);

    expect(find.byKey(Key('drill-list-$food')), findsOne);
    expect(find.byKey(Key('drill-total-$food')), findsOne);
    expect(find.textContaining('61%'), findsOne); // 12 500 / 20 500 share
    // The drill list speaks ledger-row: the category title appears per row.
    expect(
      find.descendant(
        of: find.byKey(Key('drill-list-$food')),
        matching: find.text('Food'),
      ),
      findsNWidgets(2),
    );
    // Rent rows stay out of the Food drill.
    expect(
      find.descendant(
        of: find.byKey(Key('drill-list-$food')),
        matching: find.text('Rent'),
      ),
      findsNothing,
    );

    await db.close();
  });

  testWidgets('top merchants list shows spend and row counts', (tester) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await spend(
      repo,
      catId: food,
      date: thisMonth,
      minor: 6000,
      merchant: 'Food Co',
    );
    await spend(
      repo,
      catId: food,
      date: thisMonth,
      minor: 1500,
      merchant: 'Food Co',
    );
    await pumpReports(tester, repo);

    // The segments row joined the header, so the merchants card now sits
    // past the 800×600 test viewport — scroll it into view before reading.
    await tester.scrollUntilVisible(find.textContaining('Food Co'), 120);
    await settle(tester);

    expect(find.textContaining('Food Co'), findsOne);
    expect(find.text('${Money(7500, usd).format()} · 2'), findsOne);
    expect(find.byKey(Key('merchants-empty')), findsNothing);

    await db.close();
  });

  testWidgets('the stepper walks back; the future is not navigable', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await spend(repo, catId: food, date: prevMonth, minor: prevDays * 1000);
    await pumpReports(tester, repo);

    // At the current month the forward chevron is dead (§2.1).
    expect(find.text(monthTitle(monthIndexOf(now))), findsOne);
    expect(
      tester.widget<IconButton>(find.byKey(Key('month-next'))).onPressed,
      isNull,
    );
    // This month has no spend: honest empty states on both cards (§2.1).
    expect(find.byKey(Key('donut-empty')), findsOne);
    expect(
      find.text('Merchant stats fill in as you scan or import.'),
      findsOne,
    );

    await tester.tap(find.byKey(Key('month-prev')));
    await settle(tester);

    expect(find.text(monthTitle(monthIndexOf(now) - 1)), findsOne);
    expect(
      tester.widget<IconButton>(find.byKey(Key('month-next'))).onPressed,
      isNotNull,
    );
    // A past month swaps the run-rate for the per-day average (§2.1).
    expect(find.byKey(Key('kpi-daily-avg')), findsOne);
    expect(kpiValue('kpi-daily-avg', Money(1000, usd).format()), findsOne);

    await db.close();
  });

  testWidgets('service maps merchants and period for loadMonth', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await spend(
      repo,
      catId: food,
      date: thisMonth,
      minor: 4000,
      merchant: 'Corner Market',
    );
    final report = await ReportsService(
      repo,
    ).loadMonth(DateTime(now.year, now.month));
    expect(report.yearMonth, isNotEmpty);
    expect(report.isCurrent, isTrue);
    expect(report.pace, isNotNull);
    expect(report.merchants.single.merchantName, 'Corner Market');
    expect(report.categoryNames[food], 'Food');
    expect(report.totals.spentMinor, 4000);
    await db.close();
  });
}
