import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'day_label.dart';
import 'view_models.dart';

/// One transaction (design §2.1): icon, title (+ optional memo), right-aligned
/// amount. 64 dp row, horizontal padding = space-4. Expense amount is
/// `onSurface` with a `−`, income is `primary` with a `+` — color never carries
/// meaning on its own (§5: sign **and** word).
///
/// E5 §6: a foreign row saved without an FX rate gets a quiet amber
/// "No rate" under the amount; tapping the row opens the detail sheet.
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.tile, this.onTap});

  final EntryTile tile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountColor = tile.isExpense ? scheme.onSurface : scheme.primary;

    return Semantics(
      // TalkBack: ONE node, "Coffee, Lunch, 12 dollars 40 cents, Oct 29" (§5);
      // excludeSemantics keeps the child texts from leaking as extra nodes.
      // U+2212/+ read as "minus"/"plus" — sign and word, never color alone.
      button: true,
      excludeSemantics: true,
      label:
          '${tile.title}'
          '${tile.memo == null || tile.memo!.isEmpty ? '' : ', ${tile.memo}'}'
          ', ${tile.amountDisplay()}, ${DayLabel.of(tile.day)}'
          '${tile.missingRate ? ', no exchange rate' : ''}',
      child: ConstrainedBox(
        // #48 (E3 audit, bench Flip6 2026-11-09): a hard 64 dp box overflowed
        // every row at 200 % font scale — the sub-label clipped away. minHeight
        // keeps the compact rhythm at normal scales; the row now grows to fit
        // whatever the user's text size demands. The centered Column keeps the
        // old vertical alignment when there is slack to distribute.
        constraints: const BoxConstraints(minHeight: Tokens.rowHeight),
        child: Padding(
          // Breathing room for grown rows so a scaled row never touches its
          // neighbours; at normal scales it stays inside the 64 dp rhythm.
          padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
          child: InkWell(
            onTap: onTap,
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
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tile.amountDisplay(),
                      style: Tokens.amount(
                        context,
                      ).copyWith(color: amountColor),
                    ),
                    if (tile.missingRate)
                      // The amber whisper (§6): signposted, never blocking —
                      // the row is real, only its base snapshot is absent.
                      Text(
                        'No rate',
                        key: const Key('no-rate'),
                        style: Tokens.body(context).copyWith(
                          fontSize: Tokens.labelCapsSize,
                          color: Tokens.warning,
                        ),
                      ),
                  ],
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
