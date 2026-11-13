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

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/money_display.dart';

/// Direction of a ledger movement. Presentation-side projection of a stored
/// transaction; the drift row lands in #17 and maps onto these.
enum EntryKind { expense, income }

/// Everything [TransactionRow] renders for one transaction (design §2.1).
/// Deliberately a dumb view-model so the widgets are golden/widget-testable
/// now, independent of the repository. Amount is stored **unsigned**; the
/// expense/income sign is added at display time (see [MoneyDisplay]).
@immutable
final class EntryTile {
  const EntryTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.amount,
    required this.kind,
    required this.day,
    this.memo,
    this.missingRate = false,
  });

  final int id;
  final IconData icon;
  final String title;

  /// Entry day — used only in the row's TalkBack label (§5's example ends
  /// with "Oct 29"); the visual date lives in the day-group header.
  final DateTime day;

  /// Optional second line; empty/null renders the single-line variant.
  final String? memo;

  /// E5 §6: a foreign-currency row saved without a rate — the row shows a
  /// quiet amber "No rate" so the missing snapshot is visible, not silent.
  final bool missingRate;

  /// Non-negative magnitude; sign comes from [kind].
  final Money amount;
  final EntryKind kind;

  bool get isExpense => kind == EntryKind.expense;

  String amountDisplay() => MoneyDisplay.signed(amount, isExpense: isExpense);
}

/// One month's headline numbers for [BalanceStrip] (design §2.1). Income and
/// expenses are unsigned totals ("the label carries the sign"); net may go
/// negative and renders with U+2212 in that case.
@immutable
final class BalanceSummary {
  const BalanceSummary({required this.income, required this.expenses});

  final Money income;
  final Money expenses;

  Money get net => income - expenses;

  String incomeDisplay() => income.format();
  String expensesDisplay() => expenses.format();
  String netDisplay() => MoneyDisplay.net(net);
}
