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
    final txs = await _engineRows(month.startDay, month.endDay - 1, base);
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

  /// Month transactions as engine inputs for a day window, in base minor
  /// units and with the merchant denormalized for the E4 aggregates.
  Future<List<EngineTx>> _engineRows(int from, int to, Currency base) async {
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
