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

// Owner IA pass, 2026-11-05 (second cut): the Receipts and Bills panels add
// through the SAME affordance — a quiet text-icon bar under the list, primary
// on the left, the document scanner on its right. It replaces the Receipts
// FABs so no panel on the home screen parks its add in a different corner.
// The halves are bounded and scale down rather than overflow on narrow
// phones (320 dp is a phone, not a torture test).
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The standard home-panel add bar. `secondary` (usually the document
/// scanner) is *hidden*, never disabled, when a surface can't offer it —
/// the same no-dead-end rule the Bills tab shipped with.
class PanelAddBar extends StatelessWidget {
  const PanelAddBar({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space2),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: primary,
              ),
            ),
            if (secondary != null)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: secondary!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
