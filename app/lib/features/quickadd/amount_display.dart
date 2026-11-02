import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'amount_pad.dart';

/// §2.2 item 2: right-aligned 40 pt tabular value, leading symbol 24 pt
/// onSurfaceVariant, `0` dimmed until the first digit.
///
/// Shared: QuickAdd renders this bare; the capture Review sheet may wrap it
/// in an uncertainty outline (E2 §2.3) — the *display* stays identical, so
/// the E1 golden of this hero cannot drift.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.pad, required this.currency});

  final AmountPad pad;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // §5: the hero is the one amount that shrink-wraps under text scale —
    // FittedBox scaleDown keeps long amounts readable instead of clipped.
    return Semantics(
      label: 'Amount ${pad.display}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currency.symbol,
              style: TextStyle(fontSize: 24, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: Tokens.space2),
            Text(
              pad.display,
              key: const Key('amount-value'),
              style: Tokens.amount(context, size: Tokens.amountHeroSize)
                  .copyWith(
                    color: pad.isPlaceholder
                        ? scheme.outline
                        : scheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
