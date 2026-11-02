// E4 B4 — the Year and Budget-vs-actual segments (spec §2.2/§2.3) and the
// two entrances (§1): the home month header's reports icon and the Budgets
// sheet's icon into the Actual segment. Year aggregation itself is unit-
// tested via ReportsService; these tests pin the wiring: twelve groups, the
// drawn average line, the bar-tap handoff to Month, disabled next-year at
// today, and the Actual segment's one-source rows.
//
// Same drift rules as reports_screen_test.dart: in-memory db, closed inside
// the test body.
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show LedgerScreen, monthIndexOf, monthTitle;
import 'package:local_budget/features/reports/reports_screen.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5);
  final prevMonth = DateTime(now.year, now.month - 1, 10);
  final ym = yearMonthOf(DateTime(now.year, now.month));
  final prevYm = yearMonthOf(DateTime(now.year, now.month - 1));

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

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

  /// Drift hands results back on the real event loop, which fake-async
  /// `pumpAndSettle` can outrun under parallel-test CPU pressure — pump a
  /// short ceiling so every awaiting chain in the service gets flushed.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpReports(
    WidgetTester tester,
    LedgerRepository repo, {
    ReportSegment? segment,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReportsScreen(
          repository: repo,
          initialSegment: segment ?? ReportSegment.month,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> toYear(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('segment-year')));
    await settle(tester);
  }

  BarChart theChart(WidgetTester tester) =>
      tester.widget<BarChart>(find.byType(BarChart));

  testWidgets('Year: twelve bars, the drawn average, table reading', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await spend(
      repo,
      catId: food,
      date: DateTime(now.year, 1, 3),
      minor: 120000,
    );
    await spend(
      repo,
      catId: food,
      date: DateTime(now.year, 2, 3),
      minor: 60000,
    );
    await pumpReports(tester, repo);
    await toYear(tester);

    // §2.2: always twelve groups — an empty month is a zero bar, not a gap.
    expect(theChart(tester).data.barGroups.length, 12);
    // The average is drawn (dashed HorizontalLine), not just meant:
    // 180000 total / 12 months = 15000.
    final line = theChart(tester).data.extraLinesData.horizontalLines.single;
    expect(line.y, 15000.0);
    expect(
      find.text(
        'Total ${Money(180000, usd).format()}'
        '  ·  ${Money(15000, usd).format()} avg',
      ),
      findsOne,
    );
    // §6: the chart carries the whole year as one spoken table row set.
    final label = tester
        .widget<Semantics>(
          find
              .ancestor(
                of: find.byType(BarChart),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .label!;
    expect(label, contains('January, ${Money(120000, usd).format()}'));
    // Top categories: Food owns 100% of the year.
    expect(find.text('Food'), findsOne);
    expect(find.textContaining('100%'), findsWidgets);
    // Current year is the frontier — the future is not navigable (§2.1).
    expect(find.text('${now.year}'), findsOne);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('year-next'))).onPressed,
      isNull,
    );

    await db.close();
  });

  testWidgets('Year stepper walks back; next re-opens', (tester) async {
    final (db: db, repo: repo) = freshRepo();
    await pumpReports(tester, repo);
    await toYear(tester);

    await tester.tap(find.byKey(const Key('year-prev')));
    await settle(tester);
    expect(find.text('${now.year - 1}'), findsOne);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('year-next'))).onPressed,
      isNotNull,
    );
    // An empty year still renders the full twelve-slot table (§2.2).
    expect(theChart(tester).data.barGroups.length, 12);
    // Nothing spent → no average line to draw (§2.2 honesty).
    expect(theChart(tester).data.extraLinesData.horizontalLines, isEmpty);
    expect(find.byKey(const Key('year-cats-empty')), findsOne);

    await db.close();
  });

  testWidgets('Bar tap hands the month off to the Month segment', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await spend(
      repo,
      catId: food,
      date: DateTime(now.year, 1, 3),
      minor: 120000,
    );
    await spend(
      repo,
      catId: food,
      date: DateTime(now.year, 2, 3),
      minor: 60000,
    );
    await pumpReports(tester, repo);
    await toYear(tester);

    // January's bar is the tall leftmost group (120000 of a 138000 max).
    final rect = tester.getRect(find.byType(BarChart));
    await tester.tapAt(Offset(rect.left + rect.width / 24, rect.bottom - 12));
    await settle(tester);

    // §2.2 state handoff: Month segment, January, its KPI strip loaded.
    expect(
      find.text(monthTitle(monthIndexOf(DateTime(now.year, 1)))),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('kpi-spent')),
        matching: find.text(Money(120000, usd).format()),
      ),
      findsOne,
    );

    await db.close();
  });

  testWidgets('Actual: bar-vs-marker rows from the Budgets statuses', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    final zero = await repo.addCategory('Zero');
    // §2.3: the pinned overall row renders only when an overall target
    // exists (same rule as the Budgets tab — no target, no pinned row).
    await repo.setBudget(yearMonth: ym, limitMinor: 30000, currencyCode: 'USD');
    await repo.setBudget(
      categoryId: food,
      yearMonth: ym,
      limitMinor: 10000,
      currencyCode: 'USD',
    );
    // A zero limit is an editor placeholder — analytics hides it (§2.3).
    await repo.setBudget(
      categoryId: zero,
      yearMonth: ym,
      limitMinor: 0,
      currencyCode: 'USD',
    );
    await spend(repo, catId: food, date: thisMonth, minor: 4000);
    await pumpReports(tester, repo, segment: ReportSegment.actual);

    expect(find.byKey(const Key('actual-overall')), findsOne);
    expect(find.byKey(Key('actual-row-$food')), findsOne);
    expect(find.byKey(Key('actual-row-$zero')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(Key('actual-row-$food')),
        matching: find.text(
          'Spent ${Money(4000, usd).format()} of '
          '${Money(10000, usd).format()}',
        ),
      ),
      findsOne,
    );
    expect(find.byKey(Key('actual-marker-$food')), findsOne);
    // Rollover is off → no ghost marker anywhere (§2.3).
    expect(find.byKey(Key('actual-ghost-$food')), findsNothing);

    await db.close();
  });

  testWidgets('Actual with rollover: ghost marker at the carried limit', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    final food = await repo.addCategory('Food');
    await repo.setBudgetRollover(true);
    // Last month overran by 4000 → this month's available limit is 6000.
    await repo.setBudget(
      categoryId: food,
      yearMonth: prevYm,
      limitMinor: 10000,
      currencyCode: 'USD',
    );
    await spend(repo, catId: food, date: prevMonth, minor: 14000);
    await repo.setBudget(
      categoryId: food,
      yearMonth: ym,
      limitMinor: 10000,
      currencyCode: 'USD',
    );
    await pumpReports(tester, repo, segment: ReportSegment.actual);

    expect(find.byKey(Key('actual-ghost-$food')), findsOne);
    expect(
      find.descendant(
        of: find.byKey(Key('actual-row-$food')),
        matching: find.text(
          'Spent ${Money(0, usd).format()} of '
          '${Money(6000, usd).format()}',
        ),
      ),
      findsOne,
    );

    await db.close();
  });

  testWidgets('Actual empty-state CTA pops to the Budgets sheet', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('push-reports'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReportsScreen(
                      repository: repo,
                      initialSegment: ReportSegment.actual,
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-reports')));
    await settle(tester);
    expect(find.byKey(const Key('actual-empty')), findsOne);

    // §2.3: one gesture from "no budgets" to setting limits.
    await tester.tap(find.byKey(const Key('actual-open-budgets')));
    await settle(tester);
    expect(find.byKey(const Key('budget-prev')), findsOne);
    expect(find.text('Reports'), findsNothing);

    await db.close();
  });

  testWidgets('Home month header opens Reports', (tester) async {
    final (db: db, repo: repo) = freshRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LedgerScreen(repository: repo),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const Key('reports-open')));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Reports'), findsOne);
    // Default landing is the month view (§2.1).
    expect(find.byKey(const Key('kpi-spent')), findsOne);

    await db.close();
  });

  testWidgets('Budgets sheet icon opens Reports on the Actual segment', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('open-budgets'),
                onPressed: () => showBudgetsSheet(
                  context,
                  repository: repo,
                  monthIndex: monthIndexOf(DateTime.now()),
                ),
                child: const Text('budgets'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-budgets')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('reports-open-actual')));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Reports'), findsOne);
    final seg = tester.widget<SegmentedButton<ReportSegment>>(
      find.byType(SegmentedButton<ReportSegment>),
    );
    expect(seg.selected, {ReportSegment.actual});

    await db.close();
  });
}
