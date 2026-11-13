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
