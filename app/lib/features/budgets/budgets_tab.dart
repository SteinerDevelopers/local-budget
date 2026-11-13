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

import 'package:budget/budget.dart' show BudgetPeriodType, BudgetStatus;
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import 'budgets_service.dart';

/// The Budgets tab of the budgets sheet (design e3 §2.1): overall target
/// row, category rows with rollover badges, and the add / rollover / copy
/// footer. Everything is one scrolling column — no hidden actions (§5).
class BudgetsTab extends StatelessWidget {
  const BudgetsTab({
    super.key,
    required this.snapshot,
    required this.onEditOverall,
    required this.onEditLine,
    required this.onAdd,
    required this.onToggleRollover,
    required this.onCopyLastMonth,
  });

  final BudgetsSnapshot snapshot;
  final VoidCallback onEditOverall;
  final ValueChanged<BudgetLine> onEditLine;
  final VoidCallback onAdd;
  final ValueChanged<bool> onToggleRollover;
  final VoidCallback onCopyLastMonth;

  static const tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    if (snapshot.lines.isEmpty && snapshot.overall == null) {
      // Same empty-state grammar as the ledger's empty month.
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Expanded(
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
                  Text('No budgets yet', style: Tokens.body(context)),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    'Set a monthly target or add a category limit',
                    style: Tokens.labelCaps(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Tokens.space2),
                  // Same affordance as the list state's hint row (§2.1) —
                  // the empty month must still offer the overall target.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('budget-target-empty'),
                      onPressed: onEditOverall,
                      icon: Icon(
                        Icons.flag_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                      label: Text(
                        'Set a monthly target',
                        style: TextStyle(color: scheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Footer(
            snapshot: snapshot,
            onAdd: onAdd,
            onToggleRollover: onToggleRollover,
            onCopyLastMonth: onCopyLastMonth,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      children: [
        if (snapshot.overall == null)
          ListTile(
            key: const Key('budget-target-empty'),
            leading: Icon(
              Icons.flag_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              'Set a monthly target',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onTap: onEditOverall,
          )
        else
          _OverallRow(
            status: snapshot.overall!,
            currency: snapshot.currency,
            rollover: snapshot.rollover,
            fromMonth: _short(snapshot.previousMonthName),
            onTap: onEditOverall,
          ),
        for (final line in snapshot.lines)
          _CategoryRow(
            line: line,
            snapshot: snapshot,
            onTap: () => onEditLine(line),
          ),
        _Footer(
          snapshot: snapshot,
          onAdd: onAdd,
          onToggleRollover: onToggleRollover,
          onCopyLastMonth: onCopyLastMonth,
        ),
      ],
    );
  }

  static String _short(String month) =>
      month.length <= 3 ? month : month.substring(0, 3);

  /// 12 pt caption distinguishing a weekly/yearly row from the month's
  /// monthly rows (§2.1); Monthly stays silent.
  static String? periodCaption(String periodType) {
    final type = BudgetPeriodType.fromStorage(periodType);
    return switch (type) {
      BudgetPeriodType.monthly => null,
      BudgetPeriodType.weekly => 'Weekly',
      BudgetPeriodType.yearly => 'Yearly',
    };
  }
}

/// Overall target: 'Spent $842.10 of $1,200.00' + 6 dp bar (spec §2.1).
class _OverallRow extends StatelessWidget {
  const _OverallRow({
    required this.status,
    required this.currency,
    required this.rollover,
    required this.fromMonth,
    required this.onTap,
  });

  final BudgetStatus status;
  final Currency currency;
  final bool rollover;
  final String fromMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overspent = status.isOverspent;
    final barColor = overspent ? scheme.error : scheme.primary;
    final spent = status.spent(currency).format();
    final limit = Money(status.effectiveLimitMinor, currency).format();
    final carry = rollover ? carryBadge(status, currency) : '';
    return Semantics(
      label: 'Monthly target, spent $spent of $limit',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space4,
            vertical: Tokens.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spent $spent of $limit',
                style: TextStyle(
                  fontSize: Tokens.monthLabelSize - 4,
                  fontWeight: FontWeight.w500,
                  color: overspent ? scheme.error : null,
                  fontFeatures: BudgetsTab.tabular,
                ),
              ),
              if (carry.isNotEmpty)
                Text(
                  '$carry from $fromMonth',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: Tokens.space2),
              _ProgressBar(
                fraction: status.barFraction,
                color: barColor,
                height: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56 dp row: icon · name · 'spent / limit' · 4 dp bar, error color when
/// overspent (§2.1 — never a warning icon; the number carries it).
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.line,
    required this.snapshot,
    required this.onTap,
  });

  final BudgetLine line;
  final BudgetsSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = line.status;
    final currency = snapshot.currency;
    final overspent = status.isOverspent;
    final spent = Money(status.spentMinor, currency).format();
    final limit = Money(status.effectiveLimitMinor, currency).format();
    final carry = snapshot.rollover ? carryBadge(status, currency) : '';
    // Non-monthly rows are progress rows (§3.3), so carryBadge is always
    // empty for them and this monthly suffix is all that can render.
    final badge = carry.isEmpty
        ? null
        : '$carry from ${BudgetsTab._short(snapshot.previousMonthName)}';
    return Semantics(
      label: badge == null
          ? '$spent of $limit for ${line.name}'
          : '$spent of $limit for ${line.name}, $badge',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        key: Key('budget-row-${line.row.id}'),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            child: Row(
              children: [
                Icon(
                  ManageIcons.of(line.iconKey, line.name),
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tokens.body(context),
                            ),
                          ),
                          if (BudgetsTab.periodCaption(line.row.periodType)
                              case final caption?) ...[
                            const SizedBox(width: 4),
                            Text(
                              caption,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: spent,
                                  style: TextStyle(
                                    color: overspent
                                        ? scheme.error
                                        : scheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / $limit',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontFeatures: BudgetsTab.tabular,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.space1),
                      Row(
                        children: [
                          Expanded(
                            child: _ProgressBar(
                              fraction: status.barFraction,
                              color: overspent ? scheme.error : scheme.primary,
                              height: 4,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: Tokens.space2),
                            Text(
                              badge,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// radius-2 bar: fraction from the engine ([0, 1], full when overspent).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.fraction,
    required this.color,
    required this.height,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: height,
        backgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.snapshot,
    required this.onAdd,
    required this.onToggleRollover,
    required this.onCopyLastMonth,
  });

  final BudgetsSnapshot snapshot;
  final VoidCallback onAdd;
  final ValueChanged<bool> onToggleRollover;
  final VoidCallback onCopyLastMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (snapshot.unbudgetedCategories.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('budget-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add category budget'),
            ),
          ),
        SwitchListTile(
          key: const Key('rollover-switch'),
          contentPadding: EdgeInsets.symmetric(horizontal: Tokens.space2),
          title: const Text('Rollover'),
          subtitle: const Text('Unspent money moves into the next month'),
          value: snapshot.rollover,
          onChanged: onToggleRollover,
        ),
        if (snapshot.canCopyLastMonth)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('budget-copy'),
              onPressed: onCopyLastMonth,
              icon: const Icon(Icons.copy_all_outlined, size: 20),
              label: Text('Copy ${snapshot.previousMonthName}’s budgets'),
            ),
          ),
        const SizedBox(height: Tokens.space2),
      ],
    );
  }
}
