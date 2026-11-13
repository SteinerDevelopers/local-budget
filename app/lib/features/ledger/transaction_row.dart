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
    // Perf C (2026-11-13): the amount string is needed twice per row frame
    // (TalkBack label + visible Text). Format once per build instead of
    // twice — same string, half the work.
    final amountText = tile.amountDisplay();

    return Semantics(
      // TalkBack: ONE node, "Coffee, Lunch, 12 dollars 40 cents, Oct 29" (§5);
      // excludeSemantics keeps the child texts from leaking as extra nodes.
      // U+2212/+ read as "minus"/"plus" — sign and word, never color alone.
      button: true,
      excludeSemantics: true,
      label:
          '${tile.title}'
          '${tile.memo == null || tile.memo!.isEmpty ? '' : ', ${tile.memo}'}'
          ', $amountText, ${DayLabel.of(tile.day)}'
          '${tile.missingRate ? ', no exchange rate' : ''}',
      child: SizedBox(
        // #48 (E3 audit, bench Flip6 2026-11-09): a hard 64 dp box overflowed
        // every row at 200 % font scale and clipped the merchant sub-label.
        // The box is now scale-aware: exactly 64 dp at the default text size
        // (the 64 dp rhythm contract holds), and proportionally taller as the
        // user's text grows — a tight box that keeps everything the text
        // needs. The centered Columns re-center inside the slack unchanged.
        height: Tokens.rowHeight * _heightScale(context),
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
    );
  }
}

/// 1.0 at the default font scale, and the user's own scale above it, so the
/// row box never outgrows its own text (#48). Below default the rhythm is
/// deliberately kept — shrinking rows is not what a small-text request means.
double _heightScale(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  return scale < 1.0 ? 1.0 : scale;
}
