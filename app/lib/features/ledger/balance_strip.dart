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
      // E3 (#52, #48's precedent): the row grows with the OS text scale so
      // label and amount paint whole. 1.0 scale keeps the §2.1 56 dp box.
      height: _height * _heightScale(context),
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
          child: SizedBox.expand(
            // One shrink-fit box around the whole stat: the corridor is a
            // phone third wide and the row grows with the scale, but beyond
            // that (a wrapped "EXPENSES" at mid scales would not fit even
            // the grown box) the stack sheds only the size it lacks —
            // every digit and letter still prints, nothing clips (#52).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(), style: Tokens.labelCaps(context)),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: Tokens.amount(context).copyWith(color: valueColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip's scale rule — #48's helper verbatim: 1.0 at the default font
/// scale (the §2.1 56 dp box is untouched), the user's own scale above it.
double _heightScale(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  return scale < 1.0 ? 1.0 : scale;
}
