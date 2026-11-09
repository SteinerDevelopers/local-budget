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
  static const double _gutter = 24; // air between stats above 1.0 (#52)

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = [
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
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return SizedBox(
      // E3 (#52, #48's precedent): the row grows with the OS text scale so
      // label and amount paint whole. 1.0 scale keeps the §2.1 56 dp box.
      height: _height * _heightScale(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        child: scale <= 1.0
            // §2.1 verbatim: equal thirds, goldens byte-pinned.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [for (final s in stats) Expanded(child: s)],
              )
            // Owner review of #52: the thirds filled up at 200% and the
            // columns touched — lossless but unreadable as a table. Above
            // 1.0 the stats keep their natural width with a real gutter,
            // and the whole row takes ONE shrink factor, so the table
            // stays a table: equal columns, visible channels, no glyph
            // lost. The gutter is a layout constant; like every table
            // metric it scales with the table, keeping the channel-to-
            // text ratio the design chose.
            : SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      stats[0],
                      const SizedBox(width: _gutter),
                      stats[1],
                      const SizedBox(width: _gutter),
                      stats[2],
                    ],
                  ),
                ),
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
    // No Expanded here: at ≤1.0 the parent wraps each stat in one (the
    // §2.1 tree is unchanged); above it the parent shrink-fits the whole
    // table and the stat keeps its natural width.
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      button: onTap != null,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: MediaQuery.textScalerOf(context).scale(1.0) <= 1.0
            // §2.1 verbatim at the default scale (goldens byte-pinned;
            // the ellipsis is design-blessed at 1.0, not a bug there).
            ? Column(
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
              )
            // Above the default scale: natural width, no per-column fit —
            // the parent's single FittedBox sheds size uniformly so the
            // three columns stay equal and the gutters stay air (#52).
            : Column(
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
    );
  }
}

/// The strip's scale rule — #48's helper verbatim: 1.0 at the default font
/// scale (the §2.1 56 dp box is untouched), the user's own scale above it.
double _heightScale(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  return scale < 1.0 ? 1.0 : scale;
}
