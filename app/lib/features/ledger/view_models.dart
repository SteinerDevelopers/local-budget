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
  });

  final int id;
  final IconData icon;
  final String title;

  /// Entry day — used only in the row's TalkBack label (§5's example ends
  /// with "Oct 29"); the visual date lives in the day-group header.
  final DateTime day;

  /// Optional second line; empty/null renders the single-line variant.
  final String? memo;

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
