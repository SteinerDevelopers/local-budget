// Owner IA pass, 2026-11-05: "the bills, budget, and goals are all inside
// the manage page… buttons on the main page to switch between receipts,
// budget, bills, and goals." The budgets sheet's three bodies move up to
// the home screen under a bottom NavigationBar; this is that embedded body.
//
// Deliberate differences from the modal sheet (`budgets_sheet.dart`, kept
// for notification deep-links and widget routes):
//  · no drag bar, no sheet height — the Scaffold body fills the screen;
//  · no SegmentedButton — the bottom nav *is* the tab switch (`tab` prop);
//  · keys are `home-`prefixed so an open sheet can never collide with this.
import 'dart:async' show unawaited;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../bills/bills_service.dart';
import '../bills/bills_tab.dart';
import '../goals/goals_service.dart';
import '../goals/goals_tab.dart';
import '../capture/capture_services.dart';
import '../help/help_screen.dart';
import '../ledger/ledger_screen.dart' show monthTitle;
import '../reports/reports_screen.dart';
import 'budgets_service.dart';
import 'budgets_tab.dart';
import 'limit_editor_sheet.dart';

/// Which embedded body the bottom nav is showing (0 Bills · 1 Budgets ·
/// 2 Goals — the nav's own index minus its Receipts destination, i.e. the
/// owner's 2026-11-05 order Receipts · Bills · Budgets · Goals).
class HomePanel extends StatefulWidget {
  const HomePanel({
    super.key,
    required this.repository,
    required this.tab,
    required this.initialMonthIndex,
    this.currency,
    this.capture,
  });

  final LedgerRepository repository;
  final int tab;
  final int initialMonthIndex;
  final Currency? currency;

  /// Passed to the Bills body: "Add from a document" shows where capture
  /// exists, is hidden where it doesn't (never a dead end).
  final CaptureServices? capture;

  @override
  State<HomePanel> createState() => _HomePanelState();
}

class _HomePanelState extends State<HomePanel> {
  late final BudgetsService _service = BudgetsService(widget.repository);
  late int _index = widget.initialMonthIndex;
  late int _tab = widget.tab;
  BudgetsSnapshot? _snapshot;
  int? _snapshotIndex; // guards against a slow load for a left month
  List<BillLine> _bills = const [];
  List<Category> _billCats = const [];
  bool _billsLoaded = false;
  Currency _billCurrency = Currency.resolve('USD');
  List<GoalLine> _goals = const [];
  bool _goalsLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Eager loads, same rule as the sheet: the tab bodies read *_Loaded
    // flags, and the nav can land on Bills without Budgets ever building.
    unawaited(_loadBills());
    unawaited(_loadGoals());
  }

  @override
  void didUpdateWidget(HomePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab) setState(() => _tab = widget.tab);
    if (widget.initialMonthIndex != oldWidget.initialMonthIndex) {
      setState(() {
        _index = widget.initialMonthIndex;
        _snapshot = null;
      });
      _load();
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
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              _Chevron(
                keyName: 'home-budget-prev',
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
                keyName: 'home-budget-next',
                icon: Icons.chevron_right,
                semantic: 'Next month',
                onTap: () => _shiftMonth(1),
              ),
              _Chevron(
                keyName: 'home-reports-open-actual',
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
              _Chevron(
                keyName: 'home-budget-help',
                icon: Icons.help_outline,
                semantic: 'Help',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            0 =>
              !_billsLoaded
                  ? const KeyedSubtree(
                      key: Key('home-tab-bills'),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : KeyedSubtree(
                      key: const Key('home-tab-bills'),
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
              key: const Key('home-tab-goals'),
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
