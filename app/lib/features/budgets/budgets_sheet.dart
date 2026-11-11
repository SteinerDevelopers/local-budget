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

import 'dart:async' show unawaited;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../bills/bill_detail_sheet.dart';
import '../bills/bill_editor_sheet.dart';
import '../bills/bills_service.dart';
import '../bills/bills_tab.dart';
import '../capture/capture_services.dart';
import '../goals/goals_service.dart';
import '../goals/goals_tab.dart';
import '../help/help_screen.dart';
import '../ledger/ledger_screen.dart' show monthTitle;
import '../reports/reports_screen.dart';
import 'budgets_service.dart';
import 'budgets_tab.dart';
import 'limit_editor_sheet.dart';

/// Budgets & bills sheet — from the ledger's Expenses stat or Reports
/// (design e3 §2.1; the duplicate Manage entry point was removed
/// 2026-11-06 — the bottom nav is the primary home). A near-full-height
/// sheet: budgets live next to the ledger (E1 IA decision).
/// [focusBillId] (§5, notification tap) lands on the Bills tab with that
/// rule's occurrence sheet open.
Future<void> showBudgetsSheet(
  BuildContext context, {
  required LedgerRepository repository,
  required int monthIndex,
  Currency? currency,
  int? focusBillId,
  CaptureServices? capture,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => BudgetsSheet(
    repository: repository,
    initialMonthIndex: monthIndex,
    currency: currency,
    focusBillId: focusBillId,
    capture: capture,
  ),
);

class BudgetsSheet extends StatefulWidget {
  const BudgetsSheet({
    super.key,
    required this.repository,
    required this.initialMonthIndex,
    this.currency,
    this.focusBillId,
    this.capture,
  });

  final LedgerRepository repository;
  final int initialMonthIndex;
  final Currency? currency;
  final int? focusBillId;

  /// Bills body's "Add from a document" (2026-11-05 tester note); null
  /// hides the button, same contract as everywhere else.
  final CaptureServices? capture;

  @override
  State<BudgetsSheet> createState() => _BudgetsSheetState();
}

class _BudgetsSheetState extends State<BudgetsSheet> {
  late final BudgetsService _service = BudgetsService(widget.repository);
  late int _index = widget.initialMonthIndex;
  int _tab = 0; // 0 Budgets · 1 Bills · 2 Goals
  BudgetsSnapshot? _snapshot;
  int? _snapshotIndex; // guards against a slow load for a left month
  List<BillLine> _bills = const [];
  List<Category> _billCats = const [];
  bool _billsLoaded = false;
  Currency _billCurrency = Currency.resolve('USD');
  late final Future<void> _billsFuture;
  List<GoalLine> _goals = const [];
  bool _goalsLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Kick the bills load NOW: the tab body only reads `_billsLoaded`, so a
    // lazy future here would never start when the user just taps the tab.
    _billsFuture = _loadBills();
    // Same eager rule as the bills load — the Goals body reads `_goalsLoaded`.
    unawaited(_loadGoals());
    final focus = widget.focusBillId;
    if (focus != null) _openFocused(focus);
  }

  /// Notification tap (§5): jump straight to the occurrence sheet.
  Future<void> _openFocused(int ruleId) async {
    await _billsFuture;
    if (!mounted) return;
    setState(() => _tab = 1);
    BillLine? line;
    for (final b in _bills) {
      if (b.rule.id == ruleId) {
        line = b;
        break;
      }
    }
    if (line == null) return; // deleted between tap and open
    final result = await showBillDetail(
      context,
      repository: widget.repository,
      line: line,
      categories: _billCats,
    );
    if (result == 'edit') {
      if (!mounted) return;
      final changed = await showBillEditor(
        context,
        repository: widget.repository,
        currency: _billCurrency,
        categories: _billCats,
        line: line,
      );
      if (changed == true) await _loadBills();
    } else if (result != null) {
      await _loadBills();
    }
  }

  Future<void> _loadBills() async {
    final base =
        widget.currency ??
        Currency.resolve(await widget.repository.baseCurrency() ?? 'USD');
    final lines = await loadBillLines(widget.repository);
    final cats = await widget.repository.categories(income: false);
    if (!mounted) return;
    setState(() {
      _bills = lines;
      _billCats = cats;
      _billsLoaded = true;
      _billCurrency = base;
    });
  }

  Future<void> _loadGoals() async {
    final lines = await loadGoalLines(widget.repository);
    if (!mounted) return;
    setState(() {
      _goals = lines;
      _goalsLoaded = true;
    });
  }

  Future<void> _load() async {
    final forIndex = _index;
    final snapshot = await _service.load(forIndex, currency: widget.currency);
    if (!mounted || forIndex != _index) return;
    setState(() {
      _snapshot = snapshot;
      _snapshotIndex = forIndex;
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _index += delta;
      _snapshot = null;
    });
    _load();
  }

  Future<void> _edit({BudgetLine? line, bool overall = false}) async {
    final changed = await showLimitEditor(
      context,
      repository: widget.repository,
      snapshot: _snapshot!,
      monthIndex: _index,
      line: line,
      overall: overall,
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    // A scroll-controlled sheet sits flush with the physical bottom of the
    // screen — modal useSafeArea deliberately never insets it there — so
    // the system navigation bar is ours to clear (device feedback
    // 2026-11-04 pm: the Rollover row sat under the 3-button bar).
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          children: [
            const _DragBar(),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  _Chevron(
                    keyName: 'budget-prev',
                    icon: Icons.chevron_left,
                    semantic: 'Previous month',
                    onTap: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        monthTitle(_index),
                        style: TextStyle(
                          fontSize: Tokens.monthLabelSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  _Chevron(
                    keyName: 'budget-next',
                    icon: Icons.chevron_right,
                    semantic: 'Next month',
                    onTap: () => _shiftMonth(1),
                  ),
                  // E4 §1: second Reports entrance — from the sheet that owns
                  // the limits, landing on Budget vs actual (e4-reports.md §1).
                  _Chevron(
                    keyName: 'reports-open-actual',
                    icon: Icons.insights_outlined,
                    semantic: 'Reports',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportsScreen(
                          repository: widget.repository,
                          initialSegment: ReportSegment.actual,
                        ),
                      ),
                    ),
                  ),
                  // E8 §3: Help stays one tap away on this screen too.
                  _Chevron(
                    keyName: 'budget-help',
                    icon: Icons.help_outline,
                    semantic: 'Help',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HelpScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              child: SizedBox(
                height: 40,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Budgets')),
                    ButtonSegment(value: 1, label: Text('Bills')),
                    ButtonSegment(value: 2, label: Text('Goals')),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
            ),
            const SizedBox(height: Tokens.space2),
            Expanded(
              child: switch (_tab) {
                1 =>
                  !_billsLoaded
                      ? const KeyedSubtree(
                          key: Key('tab-bills'),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : KeyedSubtree(
                          key: const Key('tab-bills'),
                          child: BillsTab(
                            repository: widget.repository,
                            bills: _bills,
                            currency: _billCurrency,
                            categories: _billCats,
                            onChanged: _loadBills,
                            capture: widget.capture,
                          ),
                        ),
                2 => KeyedSubtree(
                  key: const Key('tab-goals'),
                  child: !_goalsLoaded
                      ? const Center(child: CircularProgressIndicator())
                      : GoalsTab(
                          repository: widget.repository,
                          goals: _goals,
                          onChanged: _loadGoals,
                        ),
                ),
                _ =>
                  _snapshot == null || _snapshotIndex != _index
                      ? const Center(child: CircularProgressIndicator())
                      : BudgetsTab(
                          snapshot: _snapshot!,
                          onEditOverall: () => _edit(overall: true),
                          onEditLine: (line) => _edit(line: line),
                          onAdd: () => _edit(),
                          onToggleRollover: (v) async {
                            await widget.repository.setBudgetRollover(v);
                            await _load();
                          },
                          onCopyLastMonth: () async {
                            await _service.copyLastMonth(_index);
                            await _load();
                          },
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DragBar extends StatelessWidget {
  const _DragBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.keyName,
    required this.icon,
    required this.semantic,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key(keyName),
      icon: Icon(icon, size: 28),
      tooltip: semantic,
      onPressed: onTap,
    );
  }
}
