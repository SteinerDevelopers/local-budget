import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'view_models.dart';

/// One transaction (design §2.1): icon, title (+ optional memo), right-aligned
/// amount. 64 dp row, horizontal padding = space-4. Expense amount is
/// `onSurface` with a `−`, income is `primary` with a `+` — color never carries
/// meaning on its own (§5: sign **and** word).
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.tile});

  final EntryTile tile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountColor = tile.isExpense ? scheme.onSurface : scheme.primary;

    return Semantics(
      // TalkBack: one node, "Coffee, Lunch, 12 dollars 40 cents" (§5).
      button: true,
      label:
          '${tile.title}'
          '${tile.memo == null || tile.memo!.isEmpty ? '' : ', ${tile.memo}'}'
          ', ${tile.amountDisplay()}',
      child: SizedBox(
        height: Tokens.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
          child: Row(
            children: [
              Icon(tile.icon, size: 24, color: scheme.onSurfaceVariant),
              const SizedBox(width: Tokens.space4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tile.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(context),
                    ),
                    if (tile.memo != null && tile.memo!.isNotEmpty)
                      Text(
                        tile.memo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(context).copyWith(
                          fontSize: Tokens.labelCapsSize,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.space3),
              Text(
                tile.amountDisplay(),
                style: Tokens.amount(context).copyWith(color: amountColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
