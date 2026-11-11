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

// #37 — Goals tab (design e3 §2.4). Rows: icon, name, saved / target and
// the same 4 dp bar geometry as the ledger's budget rows (§2.1). Dumb:
// the parent owns loading; every mutation returns and the parent reloads.
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/panel_add_bar.dart';
import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import 'goal_detail_sheet.dart';
import 'goal_editor_sheet.dart';
import 'goals_service.dart';

class GoalsTab extends StatelessWidget {
  const GoalsTab({
    super.key,
    required this.repository,
    required this.goals,
    required this.onChanged,
  });

  final LedgerRepository repository;
  final List<GoalLine> goals;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      // Owner consistency pass, 2026-11-06: same grammar as Receipts and
      // Bills — centered empty body, shared add bar pinned at the bottom;
      // the key stays `goal-add-empty`.
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: Tokens.space3),
                    Text('No goals yet', style: Tokens.body(context)),
                    const SizedBox(height: Tokens.space1),
                    Text(
                      'Money set aside here is a transfer — it never '
                      'counts as spending.',
                      style: Tokens.labelCaps(context),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          PanelAddBar(
            primary: TextButton.icon(
              key: const Key('goal-add-empty'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add goal'),
              onPressed: () => _add(context),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            itemCount: goals.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, i) =>
                _GoalRow(line: goals[i], onTap: () => _open(context, goals[i])),
          ),
        ),
        // Owner consistency pass, 2026-11-06: this hand-rolled SafeArea/
        // Align row rendered the same thing PanelAddBar's left slot does —
        // now it *is* the shared widget, so all four tabs add through one.
        PanelAddBar(
          primary: TextButton.icon(
            key: const Key('goal-add'),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add goal'),
            onPressed: () => _add(context),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final changed = await showGoalEditor(context, repository: repository);
    if (changed == true) await onChanged();
  }

  Future<void> _open(BuildContext context, GoalLine line) async {
    final result = await showGoalDetail(
      context,
      repository: repository,
      line: line,
    );
    if (result == 'edit') {
      if (!context.mounted) return;
      final changed = await showGoalEditor(
        context,
        repository: repository,
        goal: line.goal,
      );
      if (changed == true) await onChanged();
    } else {
      // Unconditional: transfers mutate inside the detail sheet, and a
      // swipe-dismiss returns null — the list must still catch up.
      await onChanged();
    }
  }
}

/// 56 dp row: icon · name · 'saved / target' · 4 dp bar (§2.1 geometry).
/// Open-ended goals skip the bar — a plain total, never a fake 100 %.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.line, required this.onTap});

  final GoalLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = line.fraction;
    return InkWell(
      key: Key('goal-row-${line.goal.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space2,
          vertical: Tokens.space2,
        ),
        child: Row(
          children: [
            Icon(
              ManageIcons.of(line.goal.icon, line.goal.name),
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.goal.name,
                          style: Tokens.body(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Tokens.space2),
                      Text(
                        line.target == null
                            ? line.saved.format()
                            : '${line.saved.format()} / ${line.target!.format()}',
                        style: Tokens.labelCaps(context),
                      ),
                    ],
                  ),
                  if (fraction != null) ...[
                    const SizedBox(height: Tokens.space1),
                    _Bar(fraction: fraction),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same geometry as the budgets rows (§2.1): 4 dp tall, radius 2. Reaching
/// the target is good news, so the bar stays `primary` — never `error`.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) => Semantics(
        label: '${(fraction * 100).round()}% of target',
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
