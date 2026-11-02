import 'package:budget/budget.dart';
import 'package:test/test.dart';

int d(int y, int m, int day) => dayOf(DateTime.utc(y, m, day));

EngineTx tx(
  int y,
  int m,
  int day,
  int minor, {
  int cat = 1,
  bool income = false,
  bool transfer = false,
  String? merchant,
}) =>
    EngineTx(
      dateDays: d(y, m, day),
      baseAmountMinor: minor,
      categoryId: cat,
      isIncome: income,
      isGoalTransfer: transfer,
      merchantName: merchant,
    );

void main() {
  const engine = ReportEngine();
  final nov = BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 11, 2));

  group('monthTotals', () {
    test('splits spend, income; excludes goal transfers and other months', () {
      final totals = engine.monthTotals(nov, [
        tx(2026, 11, 5, 1200),
        tx(2026, 11, 6, 800),
        tx(2026, 11, 7, 5000, income: true),
        tx(2026, 11, 8, 900, transfer: true),
        tx(2026, 10, 31, 777),
        tx(2026, 12, 1, 777),
      ]);
      expect(totals.spentMinor, 2000);
      expect(totals.incomeMinor, 5000);
      expect(totals.netMinor, 3000);
    });

    test('negative expense rows count back (§3.1 refund semantics)', () {
      final totals = engine.monthTotals(nov, [
        tx(2026, 11, 5, 1500),
        tx(2026, 11, 9, -400),
      ]);
      expect(totals.spentMinor, 1100);
    });

    test('empty month is all zeros', () {
      final totals = engine.monthTotals(nov, const []);
      expect(totals.spentMinor, 0);
      expect(totals.incomeMinor, 0);
      expect(totals.netMinor, 0);
    });
  });

  group('categoryTotals', () {
    test('shares sum to exactly 10 000 bp — residue lands on the last slice',
        () {
      final rows = engine.categoryTotals(nov, [
        tx(2026, 11, 1, 100, cat: 7),
        tx(2026, 11, 2, 100, cat: 3),
        tx(2026, 11, 3, 100, cat: 5),
      ]);
      expect(rows.map((r) => r.shareBp), [3333, 3333, 3334]);
      expect(rows.fold(0, (int s, r) => s + r.shareBp), 10000);
    });

    test('sorted by spend desc, ties by category id asc', () {
      final rows = engine.categoryTotals(nov, [
        tx(2026, 11, 1, 500, cat: 9),
        tx(2026, 11, 2, 900, cat: 4),
        tx(2026, 11, 3, 500, cat: 2),
      ]);
      expect(rows.map((r) => r.categoryId), [4, 2, 9]);
    });

    test('zero net categories drop out; empty month returns no rows', () {
      final rows = engine.categoryTotals(nov, [
        tx(2026, 11, 1, 700, cat: 1),
        tx(2026, 11, 2, -700, cat: 2), // refund ate the category
      ]);
      expect(rows.map((r) => r.categoryId), [1]);
      expect(rows.single.shareBp, 10000);
      expect(engine.categoryTotals(nov, const []), isEmpty);
    });

    test('income and transfers never enter the donut', () {
      final rows = engine.categoryTotals(nov, [
        tx(2026, 11, 1, 400, cat: 1, income: true),
        tx(2026, 11, 2, 400, cat: 2, transfer: true),
        tx(2026, 11, 3, 400, cat: 3),
      ]);
      expect(rows.single.categoryId, 3);
      expect(rows.single.shareBp, 10000);
    });
  });

  group('topMerchants', () {
    test('skips rows without a merchant, counts rows, honours limit', () {
      final rows = engine.topMerchants(
          nov,
          [
            tx(2026, 11, 1, 300, merchant: 'Food Co'),
            tx(2026, 11, 2, 200, merchant: 'Food Co'),
            tx(2026, 11, 3, 900, merchant: 'Rent LLC'),
            tx(2026, 11, 4, 9999), // no merchant — invisible
            tx(2026, 11, 5, 400, merchant: 'GasGo'),
            tx(2026, 11, 6, 100, merchant: 'Fun Place'),
            tx(2026, 11, 7, 100, merchant: 'Other Spot'),
          ],
          limit: 4);
      expect(rows.map((r) => r.merchantName),
          ['Rent LLC', 'Food Co', 'GasGo', 'Fun Place']);
      final food = rows[1];
      expect(food.spentMinor, 500);
      expect(food.count, 2);
    });

    test('ties break by name ascending (deterministic for goldens)', () {
      final rows = engine.topMerchants(nov, [
        tx(2026, 11, 1, 250, merchant: 'Zeta Mart'),
        tx(2026, 11, 2, 250, merchant: 'Alpha Mart'),
      ]);
      expect(rows.map((r) => r.merchantName), ['Alpha Mart', 'Zeta Mart']);
    });

    test('income never counts toward merchant spend', () {
      expect(
          engine.topMerchants(
              nov, [tx(2026, 11, 1, 900, income: true, merchant: 'Employer')]),
          isEmpty);
    });
  });

  group('yearTotals', () {
    test('twelve explicit buckets; neighbours and income excluded', () {
      final buckets = engine.yearTotals(2026, [
        tx(2025, 12, 31, 111),
        tx(2026, 1, 1, 100),
        tx(2026, 2, 14, 250),
        tx(2026, 11, 2, 400, income: true),
        tx(2026, 12, 31, 70),
        tx(2027, 1, 1, 111),
      ]);
      expect(buckets.length, 12);
      expect(buckets.first.yearMonth, '2026-01');
      expect(buckets.first.spentMinor, 100);
      expect(buckets[1].spentMinor, 250);
      expect(buckets[10].spentMinor, 0); // income-only November
      expect(buckets[11].spentMinor, 70);
      expect(buckets.fold(0, (int s, b) => s + b.spentMinor), 420);
    });

    test('leap-day row lands in February', () {
      final buckets = engine.yearTotals(2028, [tx(2028, 2, 29, 50)]);
      expect(buckets[1].yearMonth, '2028-02');
      expect(buckets[1].spentMinor, 50);
    });
  });

  group('pacing', () {
    test('day 1 projects the first day across the whole month', () {
      final pace =
          engine.pacing(nov, [tx(2026, 11, 1, 100)], todayDays: d(2026, 11, 1));
      // November has 30 days: 100 × 30 ÷ 1.
      expect(pace!.projectedMinor, 3000);
    });

    test('mid-month run-rate scales linearly', () {
      final pace = engine.pacing(nov, [tx(2026, 11, 5, 900)],
          todayDays: d(2026, 11, 15));
      // 900 × 30 ÷ 15 = 1800.
      expect(pace!.projectedMinor, 1800);
    });

    test('last day projects the actuals back to themselves', () {
      final pace = engine.pacing(nov, [tx(2026, 11, 30, 1234)],
          todayDays: d(2026, 11, 30));
      expect(pace!.projectedMinor, 1234);
    });

    test('null for a complete month or a day that has not started', () {
      expect(
          engine.pacing(nov, [tx(2026, 11, 5, 900)], todayDays: d(2026, 12, 1)),
          isNull);
      expect(
          engine.pacing(nov, [tx(2026, 11, 5, 900)],
              todayDays: d(2026, 10, 31)),
          isNull);
    });

    test('a net-negative month clamps the projection at zero', () {
      final pace = engine.pacing(
          nov,
          [
            tx(2026, 11, 2, 100),
            tx(2026, 11, 3, -300),
          ],
          todayDays: d(2026, 11, 3));
      expect(pace!.projectedMinor, 0);
    });
  });
}
