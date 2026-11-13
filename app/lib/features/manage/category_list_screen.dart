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

import 'package:data/data.dart';
import 'package:flutter/material.dart';

import 'category_edit_sheet.dart';
import 'icon_registry.dart';

/// Spec §2.4: category management is two sections (Expense / Income), each a
/// plain reorderable list with drag handles; tap renames, the header `+`
/// adds. Sections are separate [ReorderableListView]s on purpose — an item
/// can never be dragged across the section line.
class CategoryListScreen extends StatefulWidget {
  const CategoryListScreen({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends State<CategoryListScreen> {
  // watchCategories() is ordered; the section split keeps that order.
  late final Stream<List<Category>> _categories = widget.repository
      .watchCategories();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: StreamBuilder<List<Category>>(
        stream: _categories,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Category>[];
          final expense = all.where((c) => !c.isIncome).toList();
          final income = all.where((c) => c.isIncome).toList();
          return Column(
            children: [
              Expanded(
                child: _Section(
                  repository: widget.repository,
                  title: 'EXPENSE',
                  income: false,
                  categories: expense,
                ),
              ),
              Expanded(
                child: _Section(
                  repository: widget.repository,
                  title: 'INCOME',
                  income: true,
                  categories: income,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.repository,
    required this.title,
    required this.income,
    required this.categories,
  });

  final LedgerRepository repository;
  final String title;
  final bool income;
  final List<Category> categories;

  Future<void> _reorder(int oldIndex, int newIndex) async {
    // onReorderItem already reports newIndex in the list-without-the-moved-row
    // index space (Flutter ≥3.42, so fine on the CI floor).
    final ids = [for (final c in categories) c.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    // The StreamBuilder repaints from the db write; no optimistic setState.
    await repository.reorderCategories(income: income, orderedIds: ids);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // label-caps section header (§3) with the section's add button.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          child: Row(
            children: [
              // §5: EXPENSE / INCOME are announced as section headers.
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: income
                    ? 'Add income category'
                    : 'Add expense category',
                onPressed: () => showCategoryEdit(
                  context,
                  repository: repository,
                  income: income,
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: categories.length,
            // Handles are explicit (trailing drag icon) so rows stay tappable
            // for the rename sheet (§2.4 tap = rename).
            buildDefaultDragHandles: false,
            // onReorderItem (Flutter ≥3.42 — fine on the CI 3.44 floor).
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final c = categories[index];
              return ReorderableDragStartListener(
                key: ValueKey(c.id),
                index: index,
                child: ListTile(
                  leading: Icon(ManageIcons.of(c.icon, c.name)),
                  title: Text(c.name),
                  trailing: Icon(
                    Icons.drag_handle,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'Reorder $title category',
                  ),
                  onTap: () => showCategoryEdit(
                    context,
                    repository: repository,
                    income: income,
                    existing: c,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
