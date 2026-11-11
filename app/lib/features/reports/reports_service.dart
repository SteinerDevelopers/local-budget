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
import 'package:core/core.dart';
import 'package:data/data.dart';

/// Everything the Month segment renders for one month (E4 spec §2.1). The
/// aggregates come from [ReportEngine] — the same [EngineTx] rows the budget
/// engine consumes — so a report and the Budgets tab can never disagree
/// about what "spent" means. Computed before build; the widgets receive
/// finished lists (the 60 fps contract, §2.4).
class MonthReport {
  const MonthReport({
    required this.yearMonth,
    required this.currency,
    required this.totals,
    required this.categories,
    required this.categoryNames,
    required this.merchants,
    required this.isCurrent,
    required this.pace,
    required this.dailyAvgMinor,
  });

  final String yearMonth;
  final Currency currency;
  final MonthTotals totals;

  /// Category spend sorted desc, shares summing to exactly 10 000 bp —
  /// empty for a zero-spend month (the UI's empty-state signal).
  final List<CategoryTotal> categories;

  /// Display names for [categories] and the drill sheet; a missing id (a
  /// deleted category) renders as "Uncategorized" downstream.
  final Map<int, String> categoryNames;

  /// Top 5 merchants of the month (§2.1); rows without a merchant — every
  /// manual entry — are absent by design, not a gap.
  final List<MerchantTotal> merchants;

  /// The visible month contains today; the stepper already refuses to show
  /// a future month, so the other case is a past one.
  final bool isCurrent;

  /// Linear run-rate for the current month only — null for every other
  /// month (§2.1: past months swap the tile to [dailyAvgMinor]).
  final Pace? pace;

  /// Per-day average of the month's spend — the pacing tile's stand-in for
  /// past months (§2.1). Integer minor units, floor is honest here.
  final int dailyAvgMinor;

  int get totalSpentMinor => totals.spentMinor;
}

/// Everything the Year segment renders for one calendar year (E4 spec §2.2).
/// Twelve explicit buckets — a year with two months of data still paints
/// twelve bars; gaps are zeros, never absences.
class YearReport {
  const YearReport({
    required this.year,
    required this.currency,
    required this.buckets,
    required this.totalSpentMinor,
    required this.averageMinor,
    required this.topCategories,
    required this.categoryNames,
    required this.isCurrent,
    required this.currentMonth,
  });

  final int year;
  final Currency currency;

  /// Jan→Dec expense buckets from [ReportEngine.yearTotals].
  final List<MonthBucket> buckets;

  final int totalSpentMinor;

  /// The average line: year spend ÷ 12, integer (minor units).
  final int averageMinor;

  /// Top 5 categories of the year, shares of the *year's* spend (§2.2).
  final List<CategoryTotal> topCategories;
  final Map<int, String> categoryNames;

  /// The visible year contains today; the stepper refuses future years.
  final bool isCurrent;

  /// 0-based month of today, meaningful only when [isCurrent] — the bar
  /// chart paints it in the accent shade.
  final int currentMonth;
}

/// Loads report periods: drift rows → engine inputs → finished aggregates.
/// Pure reads; every exclusion rule lives in [EngineTx], not here.
class ReportsService {
  ReportsService(this._repo);

  final LedgerRepository _repo;

  static final ReportEngine _engine = const ReportEngine();

  Future<MonthReport> loadMonth(DateTime monthStart, {DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final base = Currency.resolve(await _repo.baseCurrency() ?? 'USD');
    final month = BudgetPeriod(BudgetPeriodType.monthly, monthStart);
    final txs = await engineRows(month.startDay, month.endDay - 1, base);
    final totals = _engine.monthTotals(month, txs);
    final todayDays = dayOf(DateTime.utc(clock.year, clock.month, clock.day));
    final daysInMonth = month.endDay - month.startDay;
    return MonthReport(
      yearMonth: yearMonthOf(monthStart),
      currency: base,
      totals: totals,
      categories: _engine.categoryTotals(month, txs),
      categoryNames: {for (final c in await _repo.categories()) c.id: c.name},
      merchants: _engine.topMerchants(month, txs),
      isCurrent: todayDays >= month.startDay && todayDays < month.endDay,
      pace: _engine.pacing(month, txs, todayDays: todayDays),
      dailyAvgMinor: totals.spentMinor ~/ daysInMonth,
    );
  }

  Future<YearReport> loadYear(int year, {DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final base = Currency.resolve(await _repo.baseCurrency() ?? 'USD');
    final from = dayOf(DateTime.utc(year));
    final to = dayOf(DateTime.utc(year + 1)) - 1;
    final txs = await engineRows(from, to, base);
    final buckets = _engine.yearTotals(year, txs);
    final total = buckets.fold<int>(0, (sum, b) => sum + b.spentMinor);
    // Same calendar-year anchor the yearly budget period uses (§2.2).
    final yearPeriod = BudgetPeriod(BudgetPeriodType.yearly, DateTime(year));
    return YearReport(
      year: year,
      currency: base,
      buckets: buckets,
      totalSpentMinor: total,
      averageMinor: total ~/ 12,
      topCategories: _engine.categoryTotals(yearPeriod, txs).take(5).toList(),
      categoryNames: {for (final c in await _repo.categories()) c.id: c.name},
      isCurrent: clock.year == year,
      currentMonth: clock.month - 1,
    );
  }

  /// Month transactions as engine inputs for a day window, in base minor
  /// units and with the merchant denormalized for the E4 aggregates.
  /// Public because the E7 Insights loader must reuse this exact mapping —
  /// the exclusion rules and merchant join live in ONE place (analytics
  /// may not fork the truth).
  Future<List<EngineTx>> engineRows(int from, int to, Currency base) async {
    if (from > to) return const [];
    final names = await _repo.merchantNames();
    final out = <EngineTx>[];
    for (final t in await _repo.transactionsInRange(from, to)) {
      // BudgetsService's rule, verbatim (§3.1): stored base amount at save
      // time, never re-converted; a row without one is skipped, not guessed.
      final minor = t.currencyCode == base.code
          ? t.amountMinor
          : t.baseAmountMinor;
      if (minor == null) continue;
      out.add(
        EngineTx(
          dateDays: t.dateDays,
          baseAmountMinor: minor,
          categoryId: t.categoryId ?? -1,
          isIncome: t.isIncome,
          isGoalTransfer: t.goalId != null, // §3.5 — transfers are not spend
          merchantName: t.merchantId == null ? null : names[t.merchantId],
        ),
      );
    }
    return out;
  }
}
