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

/// The report aggregates (spec E4 §3, `docs/design/e4-reports.md`).
/// Pure functions over the same [EngineTx] rows the budget engine consumes,
/// so a report and the Budgets tab can never disagree about what "spent"
/// means. Integer minor units, no clocks, no I/O — testing tier 1.
library;

import 'period.dart';

/// Spend/income/net for one period. Base-currency minor units throughout
/// (§4.2 — per-device base, converted once at save time).
final class MonthTotals {
  const MonthTotals({
    required this.spentMinor,
    required this.incomeMinor,
  });

  /// Expenses in budget scope (income and goal transfers excluded).
  final int spentMinor;

  /// Income rows only. Goal transfers are neither spend nor income (§3.5).
  final int incomeMinor;

  int get netMinor => incomeMinor - spentMinor;
}

/// Share of one category in a period's spend, in basis points (10 000 = all).
final class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.spentMinor,
    required this.shareBp,
  });

  final int categoryId;
  final int spentMinor;
  final int shareBp;
}

/// Spend at one merchant within a period, with the row count behind it.
final class MerchantTotal {
  const MerchantTotal({
    required this.merchantName,
    required this.spentMinor,
    required this.count,
  });

  final String merchantName;
  final int spentMinor;
  final int count;
}

/// One month of a year view. Missing months are explicit zero buckets so
/// the bar chart always paints twelve bars (spec §3).
final class MonthBucket {
  const MonthBucket({required this.yearMonth, required this.spentMinor});

  final String yearMonth;
  final int spentMinor;
}

/// Linear run-rate for the *current* month: spent scaled by days-in-month ÷
/// days-elapsed. Arithmetic, not advice — the UI labels it "On pace for…".
final class Pace {
  const Pace({required this.projectedMinor});

  final int projectedMinor;
}

/// An arbitrary calendar range `[startDay, endDay)` in epoch days
/// (E7 §2.1). Same closed-open convention as [BudgetPeriod], so the range
/// sheet and the month switcher can hand each other boundaries unchanged.
final class DayRange {
  const DayRange({required this.startDay, required this.endDay})
      : assert(endDay > startDay, 'range must span at least one day');

  final int startDay;

  /// Exclusive.
  final int endDay;

  bool contains(int dateDays) => dateDays >= startDay && dateDays < endDay;

  int get lengthDays => endDay - startDay;

  /// The same calendar span one year earlier — the YoY compare range
  /// (E7 §2.1). Dart normalizes a Feb-29 anchor to Mar-1 when the target
  /// year has no leap day; the day-count difference is exactly what
  /// [ReportEngine.compareRanges] normalizes for, so no special case here.
  DayRange shiftedBackYear() {
    DateTime civil(int days) => DateTime.utc(1970).add(Duration(days: days));
    final s = civil(startDay);
    final e = civil(endDay);
    return DayRange(
      startDay: dayOf(DateTime.utc(s.year - 1, s.month, s.day)),
      endDay: dayOf(DateTime.utc(e.year - 1, e.month, e.day)),
    );
  }
}

/// Result of comparing two ranges (E7 §2.1 delta card). The compare side is
/// scaled to the base range's day count before subtraction — honest math
/// the card can explain, hence both raw and normalized numbers ship.
final class RangeDelta {
  const RangeDelta({
    required this.spentMinor,
    required this.compareSpentMinor,
    required this.compareNormalizedMinor,
    required this.baseDays,
    required this.compareDays,
    required this.deltaBp,
  });

  final int spentMinor;

  /// Compare-range spend as stored.
  final int compareSpentMinor;

  /// Compare spend scaled by baseDays ÷ compareDays (integer floor).
  final int compareNormalizedMinor;

  final int baseDays;
  final int compareDays;

  /// `(spent - normalized) x 10 000 / normalized`; null when the
  /// normalized baseline is zero — the UI renders "no comparison data"
  /// instead of a divide-by-zero anecdote.
  final int? deltaBp;
}

/// Stateless evaluator next to [BudgetEngine]; the repository loads rows, the
/// widgets render these finished lists (the 60 fps contract: nothing here
/// runs inside a build).
final class ReportEngine {
  const ReportEngine();

  MonthTotals monthTotals(BudgetPeriod month, List<EngineTx> transactions) {
    var spent = 0;
    var income = 0;
    for (final t in transactions) {
      if (!month.contains(t.dateDays)) continue;
      if (t.isIncome) {
        income += t.baseAmountMinor;
      } else if (t.countsTowardBudgets) {
        spent += t.baseAmountMinor;
      }
    }
    return MonthTotals(spentMinor: spent, incomeMinor: income);
  }

  /// Per-category spend for [month], sorted by amount desc then id asc.
  /// Shares are integer basis points and always sum to exactly 10 000:
  /// every slice truncates, the last slice absorbs the rounding residue
  /// (spec §3 — goldens need deterministic sums). An all-zero (or empty)
  /// month yields an empty list; division never runs against a zero total.
  List<CategoryTotal> categoryTotals(
    BudgetPeriod month,
    List<EngineTx> transactions,
  ) {
    final byId = <int, int>{};
    for (final t in transactions) {
      if (!month.contains(t.dateDays) || !t.countsTowardBudgets) continue;
      byId.update(t.categoryId, (v) => v + t.baseAmountMinor,
          ifAbsent: () => t.baseAmountMinor);
    }
    final rows = byId.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.value != b.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    final total = rows.fold(0, (int s, e) => s + e.value);
    if (rows.isEmpty || total <= 0) return const [];
    final result = <CategoryTotal>[];
    var assigned = 0;
    for (var i = 0; i < rows.length; i++) {
      final share = i == rows.length - 1
          ? 10000 - assigned
          : rows[i].value * 10000 ~/ total;
      assigned += share;
      result.add(CategoryTotal(
        categoryId: rows[i].key,
        spentMinor: rows[i].value,
        shareBp: share,
      ));
    }
    return result;
  }

  /// Top merchants by spend for [month]; rows without a merchant are simply
  /// absent (manual entry has none — spec §4). Ties break by name asc.
  List<MerchantTotal> topMerchants(
    BudgetPeriod month,
    List<EngineTx> transactions, {
    int limit = 5,
  }) {
    final spent = <String, int>{};
    final counts = <String, int>{};
    for (final t in transactions) {
      final name = t.merchantName;
      if (name == null || name.isEmpty) continue;
      if (!month.contains(t.dateDays) || !t.countsTowardBudgets) continue;
      spent.update(name, (v) => v + t.baseAmountMinor,
          ifAbsent: () => t.baseAmountMinor);
      counts.update(name, (v) => v + 1, ifAbsent: () => 1);
    }
    final rows = spent.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.value != b.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    return [
      for (final e in rows.take(limit))
        MerchantTotal(
          merchantName: e.key,
          spentMinor: e.value,
          count: counts[e.key]!,
        ),
    ];
  }

  /// Twelve explicit buckets Jan→Dec of [year]; months without rows are
  /// zero buckets, so the chart needs no gap logic.
  List<MonthBucket> yearTotals(int year, List<EngineTx> transactions) {
    final spent = List<int>.filled(12, 0);
    for (final t in transactions) {
      if (!t.countsTowardBudgets) continue;
      final firstOfMonth = dayOf(DateTime.utc(year));
      final firstOfNext = dayOf(DateTime.utc(year + 1));
      if (t.dateDays < firstOfMonth || t.dateDays >= firstOfNext) continue;
      final month = _monthOf(t.dateDays);
      spent[month - 1] += t.baseAmountMinor;
    }
    return [
      for (var m = 1; m <= 12; m++)
        MonthBucket(
          yearMonth: '${year.toString().padLeft(4, '0')}-'
              '${m.toString().padLeft(2, '0')}',
          spentMinor: spent[m - 1],
        ),
    ];
  }

  /// Run-rate for the month containing [todayDays], or null when the month
  /// is complete or the day hasn't started (spec §3: the UI only asks for
  /// the current month, these guards keep the math total).
  Pace? pacing(BudgetPeriod month, List<EngineTx> transactions,
      {required int todayDays}) {
    if (todayDays < month.startDay || todayDays >= month.endDay) return null;
    final spent = monthTotals(month, transactions).spentMinor;
    final daysInMonth = month.endDay - month.startDay;
    final daysElapsed = todayDays - month.startDay + 1;
    final projected = spent * daysInMonth ~/ daysElapsed;
    return Pace(projectedMinor: projected < 0 ? 0 : projected);
  }

  /// Spend/income over an arbitrary range (E7 §2.1) — identical scope rules
  /// to [monthTotals]: income rows sum to income, goal transfers count
  /// nowhere, everything else is spend.
  MonthTotals rangeTotals(DayRange range, List<EngineTx> transactions) {
    var spent = 0;
    var income = 0;
    for (final t in transactions) {
      if (!range.contains(t.dateDays)) continue;
      if (t.isIncome) {
        income += t.baseAmountMinor;
      } else if (t.countsTowardBudgets) {
        spent += t.baseAmountMinor;
      }
    }
    return MonthTotals(spentMinor: spent, incomeMinor: income);
  }

  /// One bucket per calendar month the range touches, chronologically,
  /// zeros included (E7 §2.1: the compare series paints without gap
  /// logic — same philosophy as [yearTotals]).
  List<MonthBucket> rangeBuckets(DayRange range, List<EngineTx> transactions) {
    final first = DateTime.utc(1970).add(Duration(days: range.startDay));
    final last = DateTime.utc(1970).add(Duration(days: range.endDay - 1));
    final keys = <String>[];
    var y = first.year;
    var m = first.month;
    while (y < last.year || (y == last.year && m <= last.month)) {
      keys.add('${y.toString().padLeft(4, '0')}-'
          '${m.toString().padLeft(2, '0')}');
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    final spent = {for (final k in keys) k: 0};
    for (final t in transactions) {
      if (!range.contains(t.dateDays) || !t.countsTowardBudgets) continue;
      final d = DateTime.utc(1970).add(Duration(days: t.dateDays));
      final k = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}';
      spent[k] = (spent[k] ?? 0) + t.baseAmountMinor;
    }
    return [
      for (final k in keys) MonthBucket(yearMonth: k, spentMinor: spent[k]!),
    ];
  }

  /// Delta card math (E7 §2.1): compare spend is floored-scaled to the base
  /// range's day count, then differenced in basis points. Partial-month
  /// compares are therefore honest about unequal lengths, and the card can
  /// print `baseDays`/`compareDays` beside the number.
  RangeDelta compareRanges(
    DayRange base,
    DayRange compare,
    List<EngineTx> transactions,
  ) {
    final spent = rangeTotals(base, transactions).spentMinor;
    final raw = rangeTotals(compare, transactions).spentMinor;
    final normalized = raw * base.lengthDays ~/ compare.lengthDays;
    final deltaBp = normalized > 0
        ? (spent - normalized) * 10000 ~/ normalized
        : (spent == 0 ? 0 : null);
    return RangeDelta(
      spentMinor: spent,
      compareSpentMinor: raw,
      compareNormalizedMinor: normalized,
      baseDays: base.lengthDays,
      compareDays: compare.lengthDays,
      deltaBp: deltaBp,
    );
  }

  /// Calendar month (1–12) of an epoch day — civil-date inverse of [dayOf].
  static int _monthOf(int epochDay) {
    final date = DateTime.utc(1970).add(Duration(days: epochDay));
    return date.month;
  }
}
