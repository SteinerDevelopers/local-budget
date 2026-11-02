import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'view_models.dart';

/// Month headline: Income / Expenses / Net in a single 56 dp row (design §2.1).
/// Labels are `label-caps`; values are 16 pt tabular. Income & expenses render
/// as positive numbers (the label carries the sign), net uses `primary`.
class BalanceStrip extends StatelessWidget {
  const BalanceStrip({super.key, required this.summary, this.onExpensesTap});

  final BalanceSummary summary;

  /// Opens the budgets sheet — wired in B3; null keeps the stat inert
  /// (goldens unchanged).
  final VoidCallback? onExpensesTap;

  static const double _height = 56; // §2.1, not promoted to a §3 token

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Stat(
              label: 'Income',
              value: summary.incomeDisplay(),
              valueColor: scheme.onSurface,
            ),
            _Stat(
              label: 'Expenses',
              value: summary.expensesDisplay(),
              valueColor: scheme.onSurface,
              onTap: onExpensesTap,
            ),
            _Stat(
              label: 'Net',
              value: summary.netDisplay(),
              valueColor: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // §5: one TalkBack node per stat — "Income $1,200.00"; the words
    // INCOME/EXPENSES/NET carry the meaning the unsigned values drop.
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        button: onTap != null,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: Tokens.labelCaps(context)),
              const SizedBox(height: Tokens.space1),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.amount(context).copyWith(color: valueColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
