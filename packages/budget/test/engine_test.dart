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

import 'package:budget/budget.dart';
import 'package:test/test.dart';

int d(int y, int m, int day) => dayOf(DateTime.utc(y, m, day));

void main() {
  group('BudgetPeriod', () {
    test('monthly bounds are the calendar month', () {
      final mar =
          BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 3, 17));
      expect(mar.startDay, d(2026, 3, 1));
      expect(mar.endDay, d(2026, 4, 1));
      expect(mar.contains(d(2026, 3, 31)), isTrue);
      expect(mar.contains(d(2026, 4, 1)), isFalse);
    });

    test('December rolls into next year', () {
      final dec =
          BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 12, 25));
      expect(dec.endDay, d(2027, 1, 1));
    });

    test('February of a leap year includes the 29th', () {
      final feb =
          BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2028, 2, 29));
      expect(feb.startDay, d(2028, 2, 1));
      expect(feb.endDay, d(2028, 3, 1));
      expect(feb.contains(d(2028, 2, 29)), isTrue);
    });

    test('weekly is the ISO week (Monday first)', () {
      // 2026-02-04 is a Wednesday; its ISO week starts Monday 2026-02-02.
      final w = BudgetPeriod(BudgetPeriodType.weekly, DateTime.utc(2026, 2, 4));
      expect(w.startDay, d(2026, 2, 2));
      expect(w.endDay, d(2026, 2, 9));
      // A Sunday belongs to the week that started the previous December.
      final sun =
          BudgetPeriod(BudgetPeriodType.weekly, DateTime.utc(2026, 1, 4));
      expect(sun.startDay, d(2025, 12, 29));
      expect(sun.contains(d(2025, 12, 29)), isTrue);
      // A Thursday's week spans a year boundary.
      final thu =
          BudgetPeriod(BudgetPeriodType.weekly, DateTime.utc(2026, 1, 1));
      expect(thu.startDay, d(2025, 12, 29));
    });

    test('yearly is the calendar year of the visible month', () {
      final y = BudgetPeriod(BudgetPeriodType.yearly, DateTime.utc(2026, 7, 2));
      expect(y.startDay, d(2026, 1, 1));
      expect(y.endDay, d(2027, 1, 1));
    });

    test('previous() is contiguous for every type', () {
      for (final type in BudgetPeriodType.values) {
        final p = BudgetPeriod(type, DateTime.utc(2026, 3, 3));
        final prev = p.previous();
        expect(prev.endDay, p.startDay, reason: '$type contiguity');
        expect(prev.type, type);
      }
      final jan =
          BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 1, 9));
      expect(jan.previous().startDay, d(2025, 12, 1));
      final year =
          BudgetPeriod(BudgetPeriodType.yearly, DateTime.utc(2026, 5, 5));
      expect(year.previous().startDay, d(2025, 1, 1));
    });

    test('keyFor pads and follows the anchor month for all types', () {
      final anchor = DateTime.utc(2026, 1, 4); // a Sunday of ISO week 1
      expect(BudgetPeriod(BudgetPeriodType.weekly, anchor).keyFor(anchor),
          '2026-01');
      expect(
          BudgetPeriod(BudgetPeriodType.yearly, DateTime.utc(7, 3, 1))
              .keyFor(DateTime.utc(7, 3, 1)),
          '0007-03');
    });
  });

  group('spent sums', () {
    final period =
        BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 3, 10));
    final txs = [
      EngineTx(dateDays: d(2026, 3, 5), baseAmountMinor: 1200, categoryId: 1),
      EngineTx(dateDays: d(2026, 3, 8), baseAmountMinor: 300, categoryId: 2),
      // Outside the period.
      EngineTx(dateDays: d(2026, 2, 28), baseAmountMinor: 9999, categoryId: 1),
      EngineTx(dateDays: d(2026, 4, 1), baseAmountMinor: 9999, categoryId: 1),
      // Excluded rows (spec §3.1, §3.5).
      EngineTx(
          dateDays: d(2026, 3, 9),
          baseAmountMinor: 5000,
          categoryId: 1,
          isIncome: true),
      EngineTx(
          dateDays: d(2026, 3, 9),
          baseAmountMinor: 4000,
          categoryId: 1,
          isGoalTransfer: true),
      // A refund as a negative expense counts back.
      EngineTx(dateDays: d(2026, 3, 11), baseAmountMinor: -200, categoryId: 1),
    ];
    final engine = BudgetEngine();

    test('filters by period, category, income and goal transfers', () {
      final row = BudgetRow(
          categoryId: 1,
          yearMonth: '2026-03',
          type: BudgetPeriodType.monthly,
          limitMinor: 10000);
      final status = engine.statusFor(
          period: period, row: row, rowFor: (p) => null, transactions: txs);
      expect(status.spentMinor, 1000); // 1200 - 200
    });

    test('overall target sums every category', () {
      final status = engine.overallStatus(
        period: period,
        targetMinor: 20000,
        yearMonth: '2026-03',
        targetFor: (_) => null,
        transactions: txs,
      );
      expect(status.spentMinor, 1300); // + the 300 from category 2
    });
  });

  group('rollover', () {
    final dec =
        BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 12, 10));

    BudgetRow row(int year, int month, int limit) => BudgetRow(
        categoryId: 7,
        yearMonth: '$year-${month.toString().padLeft(2, '0')}',
        type: BudgetPeriodType.monthly,
        limitMinor: limit);

    EngineTx spent(int amount) => EngineTx(
        dateDays: d(2026, 11, 15), baseAmountMinor: amount, categoryId: 7);

    BudgetStatus evaluate({
      required bool rollover,
      int? novLimit,
      int novSpent = 0,
      int decLimit = 5000,
    }) {
      final rows = <String, BudgetRow>{
        if (novLimit != null) '2026-11': row(2026, 11, novLimit),
        '2026-12': row(2026, 12, decLimit),
      };
      return BudgetEngine(rolloverEnabled: rollover).statusFor(
        period: dec,
        row: rows['2026-12']!,
        rowFor: (p) => rows[_key(p)],
        transactions: [if (novLimit != null) spent(novSpent)],
      );
    }

    test('underspent surplus carries forward', () {
      final s = evaluate(rollover: true, novLimit: 5000, novSpent: 3000);
      expect(s.carryMinor, 2000);
      expect(s.effectiveLimitMinor, 7000);
      expect(s.remainingMinor, 7000);
    });

    test('surplus is capped at the current limit (never past 2x)', () {
      final s =
          evaluate(rollover: true, novLimit: 5000, novSpent: 0, decLimit: 1000);
      expect(s.carryMinor, 1000);
      expect(s.effectiveLimitMinor, 2000);
    });

    test('deficit passes through whole', () {
      // Spec §3.3 example: $50 budget overspent by $80 starts at -$30.
      final s = evaluate(rollover: true, novLimit: 5000, novSpent: 8000);
      expect(s.carryMinor, -3000);
      expect(s.effectiveLimitMinor, 2000);
      expect(s.isOverspent, isFalse);
    });

    test('a period without a row breaks the chain', () {
      final s = evaluate(rollover: true, novLimit: null, novSpent: 0);
      expect(s.carryMinor, 0);
      expect(s.effectiveLimitMinor, 5000);
    });

    test('the switch off means no carry at all', () {
      final s = evaluate(rollover: false, novLimit: 5000, novSpent: 0);
      expect(s.carryMinor, 0);
      expect(s.effectiveLimitMinor, 5000);
    });

    test('chains walk multiple periods and re-bound each hop', () {
      // Oct limit 5000 spent 4000 -> +1000; Nov effective 6000 spent 1000
      // -> +5000 raw; Dec limit 5000 caps carry at 5000 (2x exactly).
      final oct =
          BudgetPeriod(BudgetPeriodType.monthly, DateTime.utc(2026, 10, 5));
      final rows = <String, BudgetRow>{
        '2026-10': row(2026, 10, 5000),
        '2026-11': row(2026, 11, 5000),
        '2026-12': row(2026, 12, 5000),
      };
      final s = BudgetEngine(rolloverEnabled: true).statusFor(
        period: dec,
        row: rows['2026-12']!,
        rowFor: (p) => rows[_key(p)],
        transactions: [
          EngineTx(
              dateDays: d(2026, 10, 9), baseAmountMinor: 4000, categoryId: 7),
          EngineTx(
              dateDays: d(2026, 11, 9), baseAmountMinor: 1000, categoryId: 7),
        ],
      );
      expect(s.carryMinor, 5000);
      expect(s.effectiveLimitMinor, 10000);
      expect(oct.contains(d(2026, 10, 9)), isTrue);
    });

    test('chain is cut at maxChainDepth', () {
      final rows = <String, BudgetRow>{};
      // 30 consecutive months (2024-01..2026-06) of unused 1000-limit
      // rows; engine with depth 4.
      for (var i = 0; i < 30; i++) {
        final anchor = DateTime.utc(2024 + i ~/ 12, i % 12 + 1, 15);
        final p = BudgetPeriod(BudgetPeriodType.monthly, anchor);
        rows[_key(p)] = BudgetRow(
            categoryId: 7,
            yearMonth: _key(p),
            type: BudgetPeriodType.monthly,
            limitMinor: 1000);
      }
      final last = rows.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
      final engine = BudgetEngine(rolloverEnabled: true, maxChainDepth: 4);
      final s = engine.statusFor(
        period: _periodForKey(last),
        row: rows[last]!,
        rowFor: (p) => rows[_key(p)],
        transactions: const [],
      );
      // Depth 4 carries at most 3 hops of 1000: 1000 capped at 1000 each
      // hop, so effective stays exactly 2x = 2000, never 30x.
      expect(s.effectiveLimitMinor, 2000);
    });

    test('weekly rollover walks whole weeks', () {
      final w1 =
          BudgetPeriod(BudgetPeriodType.weekly, DateTime.utc(2026, 2, 4));
      final w2 =
          BudgetPeriod(BudgetPeriodType.weekly, DateTime.utc(2026, 2, 11));
      BudgetRow weekRow(int startDay) => BudgetRow(
          categoryId: 3,
          yearMonth: 'w$startDay',
          type: BudgetPeriodType.weekly,
          limitMinor: 2000);
      final s = BudgetEngine(rolloverEnabled: true).statusFor(
        period: w2,
        row: weekRow(w2.startDay),
        rowFor: (p) => p.startDay == w1.startDay || p.startDay == w2.startDay
            ? weekRow(p.startDay)
            : null,
        transactions: [
          EngineTx(
              dateDays: w1.startDay + 1, baseAmountMinor: 500, categoryId: 3),
        ],
      );
      expect(s.carryMinor, 1500);
      expect(s.effectiveLimitMinor, 3500);
    });
  });

  group('bar semantics', () {
    test('bar clamps at full while the number stays honest', () {
      const s = BudgetStatus(
        categoryId: 1,
        yearMonth: '2026-03',
        type: BudgetPeriodType.monthly,
        limitMinor: 1000,
        carryMinor: 0,
        effectiveLimitMinor: 1000,
        spentMinor: 2500,
      );
      expect(s.isOverspent, isTrue);
      expect(s.barFraction, 1.0);
      expect(s.remainingMinor, -1500);
    });

    test('zero-limit budgets: empty is 0 %, any spend is full', () {
      const empty = BudgetStatus(
        categoryId: 1,
        yearMonth: '2026-03',
        type: BudgetPeriodType.monthly,
        limitMinor: 0,
        carryMinor: 0,
        effectiveLimitMinor: 0,
        spentMinor: 0,
      );
      expect(empty.barFraction, 0.0);
      const spent = BudgetStatus(
        categoryId: 1,
        yearMonth: '2026-03',
        type: BudgetPeriodType.monthly,
        limitMinor: 0,
        carryMinor: 0,
        effectiveLimitMinor: 0,
        spentMinor: 10,
      );
      expect(spent.barFraction, 1.0);
    });
  });
}

String _key(BudgetPeriod p) {
  final anchor = _anchorOf(p);
  return p.keyFor(anchor);
}

DateTime _anchorOf(BudgetPeriod p) =>
    DateTime.utc(1970).add(Duration(days: p.startDay));

BudgetPeriod _periodForKey(String key) {
  final parts = key.split('-');
  return BudgetPeriod(BudgetPeriodType.monthly,
      DateTime.utc(int.parse(parts[0]), int.parse(parts[1]), 15));
}
