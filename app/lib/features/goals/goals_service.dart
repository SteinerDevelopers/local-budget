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

// #37 — Goals tab (design e3 §2.4). A goal movement is a transaction row
// carrying goalId; the isIncome bit is repurposed as the transfer's
// direction (false = deposit, true = withdraw). §3.5: goal rows never
// touch the ledger, the balance strip or budget sums — the repository's
// reads already exclude them, so this service only ever sees them through
// goalTransfers().
import 'package:core/core.dart' show Currency, Money;
import 'package:data/data.dart';

/// One Goals-tab row: the goal plus its saved total, computed from the
/// transfer ledger. Dumb — pure data, the widgets never do arithmetic.
class GoalLine {
  const GoalLine({
    required this.goal,
    required this.savedMinor,
    required this.transferCount,
  });

  final Goal goal;
  final int savedMinor;
  final int transferCount;

  Currency get currency => Currency.resolve(goal.currencyCode);
  Money get saved => Money(savedMinor, currency);
  Money? get target =>
      goal.targetMinor == null ? null : Money(goal.targetMinor!, currency);

  /// Clamped [0, 1] when a target exists; null for an open-ended goal —
  /// the bar then degrades to a plain total (§2.4).
  double? get fraction {
    final t = goal.targetMinor;
    if (t == null || t <= 0) return null;
    final f = savedMinor / t;
    return f.clamp(0.0, 1.0);
  }
}

/// Goals oldest-created first (repository order); saved = deposits minus
/// withdrawals. One transfers read per goal — local scale, no join needed.
Future<List<GoalLine>> loadGoalLines(LedgerRepository repo) async {
  final out = <GoalLine>[];
  for (final g in await repo.goals()) {
    final transfers = await repo.goalTransfers(g.id);
    var saved = 0;
    for (final t in transfers) {
      saved += t.isIncome ? -t.amountMinor : t.amountMinor;
    }
    out.add(
      GoalLine(goal: g, savedMinor: saved, transferCount: transfers.length),
    );
  }
  return out;
}

/// Recompute one line after a transfer (the detail sheet's self-refresh —
/// cheaper than reloading the whole tab under the sheet).
Future<GoalLine> reloadGoalLine(LedgerRepository repo, int goalId) async {
  final goals = await repo.goals(includeArchived: true);
  final goal = goals.firstWhere((g) => g.id == goalId);
  final transfers = await repo.goalTransfers(goalId);
  var saved = 0;
  for (final t in transfers) {
    saved += t.isIncome ? -t.amountMinor : t.amountMinor;
  }
  return GoalLine(
    goal: goal,
    savedMinor: saved,
    transferCount: transfers.length,
  );
}
