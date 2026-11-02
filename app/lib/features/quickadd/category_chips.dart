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
      height: 40,
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
