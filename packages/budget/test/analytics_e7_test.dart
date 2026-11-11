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

/// E7 §2 analytics-engine tests: DayRange math, range buckets, YoY compare
/// normalization, and the recurring detector (docs/design/e7-paid-pack.md).
library;

import 'package:budget/budget.dart';
import 'package:test/test.dart';

EngineTx tx(int y, int m, int d, int minor,
        {String? merchant, bool income = false}) =>
    EngineTx(
      dateDays: dayOf(DateTime.utc(y, m, d)),
      baseAmountMinor: minor,
      categoryId: 1,
      isIncome: income,
      merchantName: merchant,
    );

void main() {
  group('DayRange', () {
    test('contains is closed-open, lengthDays is exact', () {
      final r = DayRange(
        startDay: dayOf(DateTime.utc(2026, 3, 1)),
        endDay: dayOf(DateTime.utc(2026, 3, 32)), // Mar 31 inclusive
      );
      expect(r.lengthDays, 31);
      expect(r.contains(dayOf(DateTime.utc(2026, 3, 1))), isTrue);
      expect(r.contains(dayOf(DateTime.utc(2026, 3, 31))), isTrue);
      expect(r.contains(dayOf(DateTime.utc(2026, 4, 1))), isFalse);
    });

    test('shiftedBackYear keeps civil anchors and can change day count', () {
      final leap = DayRange(
        startDay: dayOf(DateTime.utc(2024, 2, 1)),
        endDay: dayOf(DateTime.utc(2024, 3, 1)), // 29 days, leap
      );
      final back = leap.shiftedBackYear();
      expect(back.lengthDays, 28); // 2023 Feb — the normalization case
      final plain = DayRange(
        startDay: dayOf(DateTime.utc(2026, 6, 1)),
        endDay: dayOf(DateTime.utc(2026, 7, 1)),
      ).shiftedBackYear();
      expect(plain.startDay, dayOf(DateTime.utc(2025, 6, 1)));
      expect(plain.endDay, dayOf(DateTime.utc(2025, 7, 1)));
    });
  });

  group('rangeTotals', () {
    test('scope rules match monthTotals: income separate, goals nowhere', () {
      final r = DayRange(
        startDay: dayOf(DateTime.utc(2026, 1, 15)),
        endDay: dayOf(DateTime.utc(2026, 2, 15)),
      );
      final rows = [
        tx(2026, 1, 10, 500), // before range
        tx(2026, 1, 15, 1000), // first day, inclusive
        tx(2026, 2, 14, 700), // last day, inclusive
        tx(2026, 2, 15, 999), // exclusive end
        tx(2026, 1, 20, 4000, income: true),
        EngineTx(
          dateDays: dayOf(DateTime.utc(2026, 1, 21)),
          baseAmountMinor: 2500,
          categoryId: 1,
          isGoalTransfer: true,
        ),
      ];
      final t = const ReportEngine().rangeTotals(r, rows);
      expect(t.spentMinor, 1700);
      expect(t.incomeMinor, 4000);
      expect(t.netMinor, 2300);
    });
  });

  group('rangeBuckets', () {
    test('zero-filled chronological months across a year boundary', () {
      final r = DayRange(
        startDay: dayOf(DateTime.utc(2025, 11, 5)),
        endDay: dayOf(DateTime.utc(2026, 2, 20)),
      );
      final buckets = const ReportEngine().rangeBuckets(r, [
        tx(2025, 11, 6, 100),
        tx(2026, 1, 31, 300),
        tx(2024, 12, 31, 9999), // outside
      ]);
      expect(buckets.map((b) => b.yearMonth),
          ['2025-11', '2025-12', '2026-01', '2026-02']);
      expect(buckets.map((b) => b.spentMinor), [100, 0, 300, 0]);
    });

    test('single-day range yields exactly one bucket', () {
      final r = DayRange(
        startDay: dayOf(DateTime.utc(2026, 5, 17)),
        endDay: dayOf(DateTime.utc(2026, 5, 18)),
      );
      final b = const ReportEngine().rangeBuckets(r, const []);
      expect(b.single.yearMonth, '2026-05');
      expect(b.single.spentMinor, 0);
    });
  });

  group('compareRanges', () {
    test('unequal lengths normalize by day count', () {
      // Feb 2024 (29d, 2900 minor) vs Feb 2025 (28d, 2800 minor): same
      // daily run-rate, so the honest delta is zero.
      final base = DayRange(
        startDay: dayOf(DateTime.utc(2025, 2, 1)),
        endDay: dayOf(DateTime.utc(2025, 3, 1)),
      );
      final cmp = DayRange(
        startDay: dayOf(DateTime.utc(2024, 2, 1)),
        endDay: dayOf(DateTime.utc(2024, 3, 1)),
      );
      final rows = [
        for (var i = 0; i < 28; i++) tx(2025, 2, i + 1, 100),
        for (var i = 0; i < 29; i++) tx(2024, 2, i + 1, 100),
      ];
      final d = const ReportEngine().compareRanges(base, cmp, rows);
      expect(d.spentMinor, 2800);
      expect(d.compareSpentMinor, 2900);
      expect(d.compareNormalizedMinor, 2800); // 2900*28~/29
      expect(d.deltaBp, 0);
      expect(d.baseDays, 28);
      expect(d.compareDays, 29);
    });

    test('delta sign and basis points', () {
      final base = DayRange(
        startDay: dayOf(DateTime.utc(2026, 1, 1)),
        endDay: dayOf(DateTime.utc(2026, 2, 1)),
      );
      final cmp = base.shiftedBackYear();
      final rows = [tx(2026, 1, 5, 11250), tx(2025, 1, 5, 9000)];
      final d = const ReportEngine().compareRanges(base, cmp, rows);
      expect(d.deltaBp, 2500); // +25.00 %
    });

    test('zero baseline: null when base spent, 0 when both empty', () {
      final base = DayRange(
        startDay: dayOf(DateTime.utc(2026, 4, 1)),
        endDay: dayOf(DateTime.utc(2026, 5, 1)),
      );
      final cmp = base.shiftedBackYear();
      final engine = const ReportEngine();
      expect(engine.compareRanges(base, cmp, [tx(2026, 4, 2, 100)]).deltaBp,
          isNull);
      expect(engine.compareRanges(base, cmp, const []).deltaBp, 0);
    });
  });

  group('RecurringDetector', () {
    List<EngineTx> monthly(
        String merchant, int startYear, int startMonth, List<int> amounts,
        {int day = 14, int stepDays = 30}) {
      var d = DateTime.utc(startYear, startMonth, day);
      return [
        for (final a in amounts)
          (() {
            final row = tx(d.year, d.month, d.day, a, merchant: merchant);
            d = d.add(Duration(days: stepDays));
            return row;
          })(),
      ];
    }

    test('steady monthly merchant is suggested with exact stats', () {
      final s = RecurringDetector.suggest(
        monthly('Netflix.com', 2026, 1, [1599, 1599, 1599, 1599]),
      );
      expect(s, hasLength(1));
      final n = s.single;
      expect(n.merchantName, 'Netflix.com');
      expect(n.hits, 4);
      expect(n.cadenceDays, 30);
      expect(n.amountAvgMinor, 1599);
      expect(n.amountCoVbp, 0);
      expect(n.totalMinor, 6396);
    });

    test('case- and punctuation-variants group as one pattern', () {
      final rows = [
        tx(2026, 1, 3, 900, merchant: 'UBER *TRIP'),
        tx(2026, 2, 2, 900, merchant: 'uber trip'),
        tx(2026, 3, 4, 900, merchant: 'Uber.Trip'),
      ];
      final s = RecurringDetector.suggest(rows);
      expect(s.single.hits, 3);
      expect(s.single.merchantName, 'Uber.Trip'); // most recent display
    });

    test('weekly cadence, sparse hits, and amount swing all reject', () {
      expect(
        RecurringDetector.suggest(
            monthly('Gym', 2026, 1, [2000, 2000, 2000], stepDays: 7)),
        isEmpty,
      );
      expect(
        RecurringDetector.suggest(monthly('Gym', 2026, 1, [2000, 2000])),
        isEmpty,
      );
      // ~26 % CoV: real utility-style variance is not a subscription.
      expect(
        RecurringDetector.suggest(
            monthly('Power Co', 2026, 1, [8000, 9500, 6200, 9100])),
        isEmpty,
      );
    });

    test('within tolerance: +/-15 % band passes, gaps outside 27-33 fail', () {
      expect(
        RecurringDetector.suggest(
            monthly('Insurance', 2026, 1, [5000, 5400, 4700])),
        hasLength(1),
      );
      // 36-day step: no cadence is "one month late", it is out of band.
      expect(
        RecurringDetector.suggest(
            monthly('LatePayer', 2025, 12, [3000, 3000, 3000], stepDays: 36)),
        isEmpty,
      );
    });

    test('same-day rows merge into one hit; income and goals never group', () {
      final rows = [
        tx(2026, 1, 10, 1000, merchant: 'Split Dinner'),
        tx(2026, 1, 10, 1000, merchant: 'Split Dinner'),
        tx(2026, 2, 9, 2000, merchant: 'Split Dinner'),
        tx(2026, 3, 11, 2000, merchant: 'Split Dinner'),
        tx(2026, 4, 10, 2000, merchant: 'Rent Ltd', income: true),
      ];
      final s = RecurringDetector.suggest(rows);
      expect(s.single.merchantName, 'Split Dinner');
      expect(s.single.hits, 3); // day 10 Jan counted once despite two rows
      expect(s.single.amountAvgMinor, 2000); // the two splits summed
      expect(s.single.amountCoVbp, 0);
    });

    test('suggestions order by total desc, ties by name', () {
      final rows = [
        ...monthly('Beta', 2026, 1, [3000, 3000, 3000]),
        ...monthly('Alpha', 2026, 1, [3000, 3000, 3000]),
        ...monthly('Big', 2026, 1, [9000, 9000, 9000]),
      ];
      final s = RecurringDetector.suggest(rows);
      expect(s.map((x) => x.merchantName), ['Big', 'Alpha', 'Beta']);
    });

    test('canonicalMerchant collapses to alphanumeric lowercase', () {
      expect(RecurringDetector.canonicalMerchant('Costco #0451 Wholesale'),
          'costco0451wholesale');
      expect(RecurringDetector.canonicalMerchant('---'), isEmpty);
    });
  });
}
