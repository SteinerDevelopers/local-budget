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

/// The budget engine (spec §3.2, §3.3): spent sums, the bounded rollover
/// chain, and the overall target. Pure functions of rows + transactions;
/// the repository loads both, the widgets render the statuses.
library;

import 'period.dart';

/// Stateless evaluator; [rolloverEnabled] is the device-wide Settings switch
/// (`budget_rollover`, default off — spec §2.1).
final class BudgetEngine {
  BudgetEngine({this.rolloverEnabled = false, this.maxChainDepth = 24});

  /// The device-wide Rollover switch.
  final bool rolloverEnabled;

  /// The chain never walks further back than this (safety valve; a monthly
  /// chain covers two years of history before it is cut with carry 0).
  final int maxChainDepth;

  /// Status for one category budget row. [rowFor] must return the stored
  /// row for any period of the same category/type (or null when none
  /// exists — a missing row breaks the rollover chain, spec §3.3).
  BudgetStatus statusFor({
    required BudgetPeriod period,
    required BudgetRow row,
    required BudgetRow? Function(BudgetPeriod period) rowFor,
    required List<EngineTx> transactions,
  }) {
    return _status(
      period: period,
      limitFor: (p) => rowFor(p)?.limitMinor,
      topLimit: row.limitMinor,
      scope: (t) => t.countsTowardBudgets && t.categoryId == row.categoryId,
      transactions: transactions,
      categoryId: row.categoryId,
      yearMonth: row.yearMonth,
      type: row.type,
    );
  }

  /// Status for the overall target row (§2.1: all expenses of the period).
  /// [targetFor] resolves the stored target per period; null breaks the
  /// chain exactly like a missing category row.
  BudgetStatus overallStatus({
    required BudgetPeriod period,
    required int targetMinor,
    required String yearMonth,
    required int? Function(BudgetPeriod period) targetFor,
    required List<EngineTx> transactions,
  }) {
    return _status(
      period: period,
      limitFor: targetFor,
      topLimit: targetMinor,
      scope: (t) => t.countsTowardBudgets,
      transactions: transactions,
      categoryId: null,
      yearMonth: yearMonth,
      type: BudgetPeriodType.monthly,
    );
  }

  /// Total spent across all accounts for the period (income, goal
  /// transfers and refunds-as-income excluded via [EngineTx]; negative
  /// expense rows count back, spec §3.1).
  int spentIn(
    BudgetPeriod period,
    List<EngineTx> transactions, {
    bool Function(EngineTx tx)? scope,
  }) {
    final inScope = scope ?? (EngineTx t) => t.countsTowardBudgets;
    var total = 0;
    for (final t in transactions) {
      if (period.contains(t.dateDays) && inScope(t)) total += t.baseAmountMinor;
    }
    return total;
  }

  BudgetStatus _status({
    required BudgetPeriod period,
    required int? Function(BudgetPeriod period) limitFor,
    required int topLimit,
    required bool Function(EngineTx tx) scope,
    required List<EngineTx> transactions,
    required int? categoryId,
    required String yearMonth,
    required BudgetPeriodType type,
  }) {
    final memo = <int, ({int effective, int carry, int spent})>{};

    ({int effective, int carry, int spent}) walk(BudgetPeriod p, int depth) {
      final cached = memo[p.startDay];
      if (cached != null) return cached;
      final limit = limitFor(p);
      if (limit == null) {
        // A period without a row is a chain break; callers handle null one
        // level up, so return a neutral zero state.
        return (
          effective: 0,
          carry: 0,
          spent: spentIn(p, transactions, scope: scope)
        );
      }
      final spent = spentIn(p, transactions, scope: scope);
      if (!rolloverEnabled || depth >= maxChainDepth) {
        final s = (effective: limit, carry: 0, spent: spent);
        memo[p.startDay] = s;
        return s;
      }
      final prev = walk(p.previous(), depth + 1);
      final broke = limitFor(p.previous()) == null;
      // Surplus carries are bounded by the current limit (effective can
      // never exceed 2x); deficits pass through whole (spec §3.3).
      final raw = broke ? 0 : prev.effective - prev.spent;
      final carry = raw > 0 ? (raw > limit ? limit : raw) : raw;
      final s = (effective: limit + carry, carry: carry, spent: spent);
      memo[p.startDay] = s;
      return s;
    }

    final top = walk(period, 0);
    // The top period's row always exists (the caller holds it), so its
    // effective limit uses topLimit defensively.
    final effective = limitFor(period) == null ? topLimit : top.effective;
    return BudgetStatus(
      categoryId: categoryId,
      yearMonth: yearMonth,
      type: type,
      limitMinor: topLimit,
      carryMinor: top.carry,
      effectiveLimitMinor: effective,
      spentMinor: top.spent,
    );
  }
}
