/// Budget periods (spec §3.1). All boundaries are epoch-day integers so the
/// engine never juggles time zones; the app converts with [dayOf].
library;

import 'package:core/core.dart' show Currency, Money;

/// How often a budget limit renews. Mirrors the drift `periodType` column.
enum BudgetPeriodType {
  monthly('monthly'),
  weekly('weekly'),
  yearly('yearly');

  const BudgetPeriodType(this.storageKey);

  /// Value stored in the `budgets.periodType` column.
  final String storageKey;

  static BudgetPeriodType fromStorage(String value) => BudgetPeriodType.values
      .firstWhere((t) => t.storageKey == value, orElse: () => monthly);
}

/// Epoch days since 1970-01-01 of a calendar date (time-of-day dropped).
int dayOf(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.difference(DateTime.utc(1970)).inDays;
}

DateTime _dateFromDay(int epochDay) =>
    DateTime.utc(1970).add(Duration(days: epochDay));

/// A budget period: `[startDay, endDay)` in epoch days.
///
/// * monthly — calendar month of [anchor].
/// * weekly  — the ISO week (Monday first) containing [anchor]. Spec §3.1:
///   v1 shows the week containing the visible month's today; the switcher
///   itself stays month-level.
/// * yearly  — calendar year of [anchor].
final class BudgetPeriod {
  BudgetPeriod(this.type, DateTime anchor)
      : startDay = _startDay(type, anchor),
        endDay = _endDay(type, anchor);

  const BudgetPeriod._(this.type, this.startDay, this.endDay);

  final BudgetPeriodType type;
  final int startDay;

  /// Exclusive.
  final int endDay;

  bool contains(int dateDays) => dateDays >= startDay && dateDays < endDay;

  /// The `yearMonth` storage key of this period — the month containing
  /// [anchor] for every type (weekly/yearly rows are keyed by their visible
  /// month; §3.1 keeps v1 at month granularity for listing).
  String keyFor(DateTime anchor) =>
      '${anchor.year.toString().padLeft(4, '0')}-${anchor.month.toString().padLeft(2, '0')}';

  /// The immediately preceding period of the same type — the link the
  /// rollover chain walks (§3.3).
  BudgetPeriod previous() {
    switch (type) {
      case BudgetPeriodType.monthly:
        final first = _dateFromDay(startDay);
        final prev = DateTime.utc(
            first.month == 1 ? first.year - 1 : first.year,
            first.month == 1 ? 12 : first.month - 1);
        return BudgetPeriod._(type, _startDay(type, prev), startDay);
      case BudgetPeriodType.weekly:
        return BudgetPeriod._(type, startDay - 7, startDay);
      case BudgetPeriodType.yearly:
        final year = _dateFromDay(startDay).year - 1;
        return BudgetPeriod._(type, dayOf(DateTime.utc(year)), startDay);
    }
  }

  static int _startDay(BudgetPeriodType type, DateTime anchor) {
    switch (type) {
      case BudgetPeriodType.monthly:
        return dayOf(DateTime.utc(anchor.year, anchor.month));
      case BudgetPeriodType.weekly:
        // DateTime.weekday is already ISO (Mon=1..Sun=7).
        return dayOf(anchor) - anchor.weekday + DateTime.monday;
      case BudgetPeriodType.yearly:
        return dayOf(DateTime.utc(anchor.year));
    }
  }

  static int _endDay(BudgetPeriodType type, DateTime anchor) {
    switch (type) {
      case BudgetPeriodType.monthly:
        return dayOf(anchor.month == 12
            ? DateTime.utc(anchor.year + 1)
            : DateTime.utc(anchor.year, anchor.month + 1));
      case BudgetPeriodType.weekly:
        return _startDay(type, anchor) + 7;
      case BudgetPeriodType.yearly:
        return dayOf(DateTime.utc(anchor.year + 1));
    }
  }
}

/// One stored budget limit row, mapped from drift (B2). Amounts are
/// base-currency minor units; the engine never sees a currency object
/// (§3.6 — limits are stored as-is and never re-written).
final class BudgetRow {
  const BudgetRow({
    required this.categoryId,
    required this.yearMonth,
    required this.type,
    required this.limitMinor,
  });

  final int categoryId;
  final String yearMonth;
  final BudgetPeriodType type;
  final int limitMinor;
}

/// The minimal transaction shape the engine needs — a projection of a drift
/// row, deliberately dumb so repositories stay dumb (spec §3 preamble).
final class EngineTx {
  const EngineTx({
    required this.dateDays,
    required this.baseAmountMinor,
    required this.categoryId,
    this.isIncome = false,
    this.isGoalTransfer = false,
    this.merchantName,
  });

  /// Epoch day of the transaction date.
  final int dateDays;

  /// Expense amount in base-currency minor units, converted once at save
  /// time (stored `fxRate`); never re-converted (§3.1).
  final int baseAmountMinor;

  final int categoryId;

  /// Income rows never feed budget progress (§3.1).
  final bool isIncome;

  /// `goalId != null` rows are hidden from budget sums (§3.5).
  final bool isGoalTransfer;

  /// Denormalized merchant for the report aggregates (E4 §4); the budget
  /// engine never reads it, so scope semantics stay untouched.
  final String? merchantName;

  bool get countsTowardBudgets => !isIncome && !isGoalTransfer;
}

/// Result of evaluating one budget row (or the overall target) for a period.
final class BudgetStatus {
  const BudgetStatus({
    required this.categoryId,
    required this.yearMonth,
    required this.type,
    required this.limitMinor,
    required this.carryMinor,
    required this.effectiveLimitMinor,
    required this.spentMinor,
  });

  /// Null for the overall target row (§2.1).
  final int? categoryId;
  final String yearMonth;
  final BudgetPeriodType type;
  final int limitMinor;

  /// Signed carry from the previous period; 0 when rollover is off or the
  /// chain is broken (§3.3). Rendered as the `+$20 from Oct` badge.
  final int carryMinor;
  final int effectiveLimitMinor;
  final int spentMinor;

  int get remainingMinor => effectiveLimitMinor - spentMinor;
  bool get isOverspent => spentMinor > effectiveLimitMinor;

  /// Fraction spent, clamped to 1.0 for the bar; the *number* stays honest
  /// even past 100 % (§2.1 — "full bar + truth number").
  double get barFraction {
    if (effectiveLimitMinor <= 0) return spentMinor > 0 ? 1 : 0;
    final f = spentMinor / effectiveLimitMinor;
    return f > 1 ? 1 : (f < 0 ? 0 : f);
  }

  Money limit(Currency currency) => Money(limitMinor, currency);
  Money spent(Currency currency) => Money(spentMinor, currency);
  Money remaining(Currency currency) => Money(remainingMinor, currency);
}
