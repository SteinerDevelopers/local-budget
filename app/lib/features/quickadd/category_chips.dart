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
import 'quick_add_sheet.dart' show CategoryOption;

/// §2.2 item 4: single scrolling FilterChip row, `⚙︎` chip last.
///
/// Shared with the capture Review sheet (E2 §2.3 item 5 — "the QuickAdd chip
/// row, same warm-state rules"), which is the reuse the E1 frame rule asks
/// for: one widget, one look, tested once.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onManage,
  });

  final List<CategoryOption> categories;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Chips grow with the system font (device feedback 2026-11-04): a
      // tight 40 dp box clipped chip glyphs at large accessibility scales.
      height: MediaQuery.textScalerOf(context).scale(40),
      child: ListView(
        // Test handle: the Manage chip sits at the end of a row that can
        // overflow with many categories (#18).
        key: const Key('chip-row'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: Tokens.space2),
              child: FilterChip(
                selected: c.id == selectedId,
                onSelected: (_) => onSelect(c.id),
                avatar: Icon(c.icon, size: 18),
                label: Text(c.name),
              ),
            ),
          if (onManage != null)
            ActionChip(
              avatar: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Manage'),
              // §2.4: jump to Manage. The sheet closes first — its chips are
              // an open-time snapshot anyway, so the next FAB re-reads.
              onPressed: () {
                Navigator.of(context).pop();
                onManage!();
              },
            ),
        ],
      ),
    );
  }
}
