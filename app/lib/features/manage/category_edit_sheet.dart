import 'package:data/data.dart';
import 'package:flutter/material.dart';

import 'icon_registry.dart';

/// Spec §2.4: tapping a category opens a rename sheet; the add button opens
/// the same sheet empty. Both pick their icon from the fixed 32-icon grid
/// (4 columns × 8 rows) — free icon picking is out of scope for E1.
Future<void> showCategoryEdit(
  BuildContext context, {
  required LedgerRepository repository,
  required bool income,

  /// Null ⇒ "add" mode; a non-null row means rename/re-icon.
  Category? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // radius-sheet token (§3).
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (sheetContext) => Padding(
    // Keep the name field visible above the keyboard.
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
    ),
    child: _CategoryEdit(
      repository: repository,
      income: income,
      existing: existing,
    ),
  ),
);

class _CategoryEdit extends StatefulWidget {
  const _CategoryEdit({
    required this.repository,
    required this.income,
    this.existing,
  });

  final LedgerRepository repository;
  final bool income;
  final Category? existing;

  @override
  State<_CategoryEdit> createState() => _CategoryEditState();
}

class _CategoryEditState extends State<_CategoryEdit> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name,
  );
  late String? _icon = widget.existing?.icon;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    if (existing == null) {
      // Append after the section's last row (spec §2.4 ordering).
      final siblings = await widget.repository.categories(
        income: widget.income,
      );
      final nextSort =
          siblings.fold<int>(
            -1,
            (max, c) => c.sortOrder > max ? c.sortOrder : max,
          ) +
          1;
      await widget.repository.addCategory(
        name,
        icon: _icon,
        sortOrder: nextSort,
        isIncome: widget.income,
      );
    } else {
      await widget.repository.updateCategory(
        existing.id,
        name: name,
        icon: _icon,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // Grid (8 rows) + field + button; the list itself scrolls.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.existing == null
                  ? (widget.income
                        ? 'New income category'
                        : 'New expense category')
                  : 'Rename category',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              // Rebuild so Save/Add enables the moment the field is non-empty.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            // label-caps section token (§3).
            Text(
              'ICON',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 12,
                letterSpacing: 0.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: GridView.count(
                crossAxisCount: 4, // 4 × 8 grid (§2.4)
                // Landscape-ish cells so a 4×8 grid fits a phone sheet
                // without absurd vertical whitespace.
                childAspectRatio: 1.6,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                primary: false,
                children: [
                  for (final entry in ManageIcons.grid.entries)
                    _IconCell(
                      iconKey: entry.key,
                      selected: _icon == entry.key,
                      onTap: () => setState(() => _icon = entry.key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(widget.existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      // The glyph itself is decorative; the key is the label (§5: no
      // color/icon-only meaning). excludeSemantics keeps this a single node.
      excludeSemantics: true,
      label: iconKey,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? theme.colorScheme.secondaryContainer : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                ManageIcons.grid[iconKey],
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
