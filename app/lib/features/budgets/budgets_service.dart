import 'package:budget/budget.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';

/// One stored category budget with its computed status and the display
/// fields the row needs (design e3 §2.1).
class BudgetLine {
  const BudgetLine({
    required this.row,
    required this.status,
    required this.name,
    required this.iconKey,
  });

  final Budget row;
  final BudgetStatus status;
  final String name;
  final String? iconKey;
}

/// Everything the Budgets tab renders for one visible month (§2.1).
class BudgetsSnapshot {
  const BudgetsSnapshot({
    required this.yearMonth,
    required this.currency,
    required this.rollover,
    required this.overall,
    required this.lines,
    required this.unbudgetedCategories,
    required this.canCopyLastMonth,
    required this.previousMonthName,
  });

  final String yearMonth;
  final Currency currency;

  /// Device-wide rollover switch (`budget_rollover`, default off, §3.3).
  final bool rollover;

  /// The overall target's status; null = no target set → tappable hint row.
  final BudgetStatus? overall;
  final List<BudgetLine> lines;

  /// Non-income categories without a budget this month — the editor's chip
  /// list (§2.2: never offer a duplicate row for the same period).
  final List<Category> unbudgetedCategories;
  final bool canCopyLastMonth;
  final String previousMonthName;
}

/// Loads the visible month: drift rows → engine inputs → statuses
/// (§3.2's mapping layer). Pure reads; every mutation goes through the
/// repository so the sheet can reload from one place.
class BudgetsService {
  BudgetsService(this._repo);

  final LedgerRepository _repo;

  Future<BudgetsSnapshot> load(
    int monthIndex, {
    Currency? currency,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final monthStart = DateTime(2000 + monthIndex ~/ 12, monthIndex % 12 + 1);
    final ym = yearMonthOf(monthStart);
    final base =
        currency ?? Currency.resolve(await _repo.baseCurrency() ?? 'USD');
    final rollover = await _repo.budgetRollover();
    final rows = await _repo.budgetsIn(ym);

    // The chain can only extend across periods that actually have rows, so
    // one floor two years (and one day two decades) back is the deepest the
    // engine will ever walk with the maxChainDepth = 24 cap.
    final stored = rollover
        ? await _repo.budgetsBetween(
            yearMonthOf(DateTime(monthStart.year - 26, 1)),
            ym,
          )
        : rows;
    // The engine's BudgetRow is category-only; the overall target lives in
    // its own lookup and existence-checking uses plain keys.
    final rowExists = <String>{};
    final engineRows = <String, BudgetRow>{};
    final overallByKey = <String, int>{};
    for (final b in stored) {
      final key = '${b.categoryId ?? -1}|${b.yearMonth}|${b.periodType}';
      rowExists.add(key);
      final catId = b.categoryId;
      if (catId == null) {
        overallByKey[key] = b.limitMinor;
      } else {
        engineRows[key] = BudgetRow(
          categoryId: catId,
          yearMonth: b.yearMonth,
          type: BudgetPeriodType.fromStorage(b.periodType),
          limitMinor: b.limitMinor,
        );
      }
    }

    // §3.1 anchors: monthly/yearly key off the visible month; weekly is the
    // ISO week containing the visible month's today (month-level switcher).
    final sameMonth =
        clock.year == monthStart.year && clock.month == monthStart.month;
    final weeklyAnchor = sameMonth ? clock : monthStart;
    BudgetPeriod periodFor(BudgetPeriodType t) => BudgetPeriod(
      t,
      t == BudgetPeriodType.weekly ? weeklyAnchor : monthStart,
    );

    // Transaction window: the visible periods, plus every period the
    // rollover chains will actually sum (chain-walkable rows only — the
    // engine's chain break at a missing row means deeper history is never
    // read, so it is never loaded either).
    var from = dayOf(DateTime.utc(2100));
    var to = 0;
    final chains = <(int, BudgetPeriodType)>[];
    Budget? overallRow;
    for (final b in rows) {
      final type = BudgetPeriodType.fromStorage(b.periodType);
      final p = periodFor(type);
      if (p.startDay < from) from = p.startDay;
      if (p.endDay - 1 > to) to = p.endDay - 1;
      if (b.categoryId == null) {
        overallRow = b;
        chains.add((-1, BudgetPeriodType.monthly));
      } else {
        chains.add((b.categoryId!, type));
      }
    }
    final hasTarget = overallRow != null;
    if (!hasTarget) {
      // The target hint row still shows month spent; keep the month window.
      final m = BudgetPeriod(BudgetPeriodType.monthly, monthStart);
      if (m.startDay < from) from = m.startDay;
      if (m.endDay - 1 > to) to = m.endDay - 1;
    }
    if (rollover) {
      for (final (catKey, type) in chains) {
        var p = periodFor(type);
        for (var i = 0; i < 24; i++) {
          final prev = p.previous();
          if (!rowExists.contains(
            '$catKey|${_ymOfDay(prev.startDay)}|${type.storageKey}',
          )) {
            break;
          }
          p = prev;
        }
        if (p.startDay < from) from = p.startDay;
      }
    }
    if (rows.isEmpty && !hasTarget) {
      // Nothing to sum anywhere: skip the transaction read entirely.
      from = 0;
      to = -1;
    }

    final txs = <EngineTx>[];
    if (from <= to) {
      for (final t in await _repo.transactionsInRange(from, to)) {
        // §3.1: stored base amount at save time, never re-converted; a row
        // without one (legacy FX gap) is skipped rather than guessed.
        final minor = t.currencyCode == base.code
            ? t.amountMinor
            : t.baseAmountMinor;
        if (minor == null) continue;
        txs.add(
          EngineTx(
            dateDays: t.dateDays,
            baseAmountMinor: minor,
            categoryId: t.categoryId ?? -1,
            isIncome: t.isIncome,
            isGoalTransfer: t.goalId != null, // §3.5: transfers are not spend
          ),
        );
      }
    }

    final engine = BudgetEngine(rolloverEnabled: rollover);
    BudgetStatus? overall;
    if (overallRow != null) {
      overall = engine.overallStatus(
        period: periodFor(BudgetPeriodType.monthly),
        targetMinor: overallRow.limitMinor,
        yearMonth: ym,
        targetFor: (p) => overallByKey['-1|${_ymOfDay(p.startDay)}|monthly'],
        transactions: txs,
      );
    }

    final cats = await _repo.categories(income: false);
    final catById = {for (final c in cats) c.id: c};
    final lines = <BudgetLine>[];
    for (final b in rows) {
      final catId = b.categoryId;
      if (catId == null) continue;
      final type = BudgetPeriodType.fromStorage(b.periodType);
      final status = engine.statusFor(
        period: periodFor(type),
        row: engineRows['$catId|$ym|${type.storageKey}']!,
        rowFor: (p) =>
            engineRows['$catId|${_ymOfDay(p.startDay)}|${type.storageKey}'],
        transactions: txs,
      );
      final cat = catById[catId];
      lines.add(
        BudgetLine(
          row: b,
          status: status,
          name: cat?.name ?? 'Deleted category',
          iconKey: cat?.icon,
        ),
      );
    }
    lines.sort((a, b) {
      final byOrder = (catById[a.row.categoryId]?.sortOrder ?? 9999).compareTo(
        catById[b.row.categoryId]?.sortOrder ?? 9999,
      );
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });

    final budgeted = {for (final b in rows) b.categoryId};
    final prevYm = yearMonthOf(DateTime(monthStart.year, monthStart.month - 1));
    final prevRows = await _repo.budgetsIn(prevYm);

    return BudgetsSnapshot(
      yearMonth: ym,
      currency: base,
      rollover: rollover,
      overall: overall,
      lines: lines,
      unbudgetedCategories: [
        for (final c in cats)
          if (!budgeted.contains(c.id)) c,
      ],
      canCopyLastMonth: prevRows.any(
        (b) => b.categoryId != null && b.periodType == 'monthly',
      ),
      previousMonthName: _monthNames[(monthStart.month + 10) % 12],
    );
  }

  /// §2.1 'Copy October's budgets': insert-only — a category that already
  /// has a monthly limit this month keeps its own number.
  Future<void> copyLastMonth(int monthIndex) async {
    final monthStart = DateTime(2000 + monthIndex ~/ 12, monthIndex % 12 + 1);
    final ym = yearMonthOf(monthStart);
    final prevYm = yearMonthOf(DateTime(monthStart.year, monthStart.month - 1));
    final current = {
      for (final b in await _repo.budgetsIn(ym))
        if (b.categoryId != null && b.periodType == 'monthly') b.categoryId,
    };
    for (final b in await _repo.budgetsIn(prevYm)) {
      final catId = b.categoryId;
      if (catId == null ||
          b.periodType != 'monthly' ||
          current.contains(catId)) {
        continue;
      }
      await _repo.setBudget(
        categoryId: catId,
        yearMonth: ym,
        limitMinor: b.limitMinor,
        currencyCode: b.currencyCode,
      );
    }
  }

  static String _ymOfDay(int epochDay) {
    final d = DateTime.fromMillisecondsSinceEpoch(
      epochDay * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

/// The `+$20.00 from Oct` badge (§3.3) — absent when carry is 0. The
/// minus sign is U+2212 like every other money surface (decision: tabular).
String carryBadge(BudgetStatus status, Currency currency) {
  final carry = status.carryMinor;
  if (carry == 0) return '';
  final sign = carry > 0 ? '+' : '\u2212';
  return '$sign${Money(carry.abs(), currency).format()}';
}
