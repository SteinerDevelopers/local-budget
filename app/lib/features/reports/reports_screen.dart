import 'package:budget/budget.dart' show CategoryTotal;
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ledger/ledger_screen.dart' show monthIndexOf, monthTitle, tileFor;
import '../ledger/transaction_row.dart';
import '../manage/icon_registry.dart';
import 'reports_service.dart';

/// The Reports screen (E4 spec §2.1). B3 ships the Month segment: header
/// stepper, KPI strip, category donut with a drill sheet, top merchants.
/// Year and Budget-vs-actual segments join the same scaffold in B4 (§9).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsService _service = ReportsService(widget.repository);

  /// Index of the visible month in the shared 2000-based calendar grid.
  int _monthIndex = monthIndexOf(DateTime.now());
  late Future<MonthReport> _report = _load();

  Future<MonthReport> _load() => _service.loadMonth(_monthStart(_monthIndex));

  /// Shifts the stepper; `+1` is unreachable from the current month (the
  /// button is disabled — the future is not navigable, §2.1).
  void _shift(int delta) {
    setState(() {
      _monthIndex += delta;
      _report = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nowIndex = monthIndexOf(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Column(
          children: [
            _Stepper(
              title: monthTitle(_monthIndex),
              canGoNext: _monthIndex < nowIndex,
              onPrev: () => _shift(-1),
              onNext: () => _shift(1),
            ),
            Expanded(
              child: FutureBuilder<MonthReport>(
                future: _report,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _LoadError(
                      onRetry: () => setState(() => _report = _load()),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _MonthView(
                    report: snap.data!,
                    repository: widget.repository,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest failure line with a retry — local reads fail only on disk trouble.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Could not load this month.', style: Tokens.body(context)),
          const SizedBox(height: Tokens.space2),
          TextButton(
            key: const Key('report-retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// `‹ November 2026 ›` — the only navigation the month view needs (§2.1).
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('month-prev'),
            tooltip: 'Previous month',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            // Fixed-ish width keeps the chevrons from dancing between months.
            width: 200,
            child: Center(
              child: Text(
                title,
                style: Tokens.monthTitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            key: const Key('month-next'),
            tooltip: 'Next month',
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// KPI strip, donut card, top merchants — data arrives finished; nothing
/// here computes (aggregates ran in the service before build, §2.4).
class _MonthView extends StatelessWidget {
  const _MonthView({required this.report, required this.repository});

  final MonthReport report;
  final LedgerRepository repository;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = report.currency;
    String money(int minor) => Money(minor, currency).format();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space4,
        Tokens.space1,
        Tokens.space4,
        Tokens.space5,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _Kpi(
                key: const Key('kpi-spent'),
                label: 'Spent',
                value: money(report.totals.spentMinor),
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: _Kpi(
                key: const Key('kpi-income'),
                label: 'Income',
                value: money(report.totals.incomeMinor),
                valueColor: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.space2),
        Row(
          children: [
            Expanded(
              child: _Kpi(
                key: const Key('kpi-net'),
                label: 'Net',
                value: money(report.totals.netMinor),
                valueColor: report.totals.netMinor >= 0
                    ? scheme.primary
                    : scheme.error,
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: report.isCurrent && report.pace != null
                  ? _Kpi(
                      key: const Key('kpi-pacing'),
                      label: 'On pace for',
                      // Arithmetic, not advice (§2.1); Help carries the caveat.
                      value: money(report.pace!.projectedMinor),
                    )
                  : _Kpi(
                      key: const Key('kpi-daily-avg'),
                      label: 'Daily average',
                      value: money(report.dailyAvgMinor),
                    ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.space4),
        _SectionCard(
          title: 'Spending by category',
          child: report.categories.isEmpty
              ? _EmptyNote(
                  key: const Key('donut-empty'),
                  text: 'No spending yet this month.',
                )
              : _Donut(
                  report: report,
                  onTapCategory: (cat) => _openDrill(context, cat),
                ),
        ),
        const SizedBox(height: Tokens.space4),
        _SectionCard(
          title: 'Top merchants',
          child: report.merchants.isEmpty
              // One honest line — manual rows have no merchant by design (§2.1).
              ? const _EmptyNote(
                  key: Key('merchants-empty'),
                  text: 'Merchant stats fill in as you scan or import.',
                )
              : Column(
                  children: [
                    for (final m in report.merchants)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Tokens.space1,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.merchantName,
                                style: Tokens.body(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: Tokens.space3),
                            Text(
                              // "Food Co · \$120.40 · 3" — name, spend, rows.
                              '${money(m.spentMinor)} · ${m.count}',
                              style: Tokens.amount(context),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Drill sheet: that category's rows for the month, in the ledger's own
  /// row style (§2.1) — a live month stream, scoped to the sheet's lifetime.
  void _openDrill(BuildContext context, CategoryTotal cat) {
    final name = report.categoryNames[cat.categoryId] ?? 'Uncategorized';
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Tokens.space4),
              child: Row(
                children: [
                  Icon(
                    ManageIcons.of(null, name),
                    size: 24,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Text(
                      name,
                      style: Tokens.body(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    // Amount and share together — the sheet explains the slice.
                    '${Money(cat.spentMinor, report.currency).format()}'
                    ' · ${(cat.shareBp / 100).round()}%',
                    key: Key('drill-total-${cat.categoryId}'),
                    style: Tokens.amount(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _DrillList(
                repository: repository,
                yearMonth: report.yearMonth,
                categoryId: cat.categoryId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of the drill: one subscription, like the ledger's month page —
/// `watchMonth` mints a fresh stream per call, so the sheet owns exactly it.
class _DrillList extends StatefulWidget {
  const _DrillList({
    required this.repository,
    required this.yearMonth,
    required this.categoryId,
  });

  final LedgerRepository repository;
  final String yearMonth;
  final int categoryId;

  @override
  State<_DrillList> createState() => _DrillListState();
}

class _DrillListState extends State<_DrillList> {
  late final Stream<List<LedgerEntryData>> _rows = widget.repository.watchMonth(
    widget.yearMonth,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerEntryData>>(
      stream: _rows,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!
            .where((r) => (r.categoryId ?? -1) == widget.categoryId)
            .toList();
        return ListView(
          key: Key('drill-list-${widget.categoryId}'),
          children: [for (final r in rows) TransactionRow(tile: tileFor(r))],
        );
      },
    );
  }
}

/// One KPI tile: small caps label above a tabular amount (§2.1 2×2 strip).
class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: Tokens.space3,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Tokens.labelCaps(context)),
            const SizedBox(height: Tokens.space1),
            Text(
              value,
              style: Tokens.amount(
                context,
              ).copyWith(color: valueColor ?? scheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Flattened card: label-caps header + finished content, one per report
/// section — same flat grammar as the rest of the app.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Tokens.labelCaps(context)),
          const SizedBox(height: Tokens.space3),
          child,
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: Tokens.body(context));
}

/// Donut of the month's category spend. Colors are positional (deterministic
/// for goldens); tap radius stays generous — slices can be thin.
class _Donut extends StatelessWidget {
  const _Donut({required this.report, required this.onTapCategory});

  final MonthReport report;
  final ValueChanged<CategoryTotal> onTapCategory;

  /// Eight fixed hues; index = position in the sorted aggregate.
  static const List<Color> _palette = [
    Color(0xFF2E7D32),
    Color(0xFF00897B),
    Color(0xFF3949AB),
    Color(0xFF7B1FA2),
    Color(0xFFC2185B),
    Color(0xFFEF6C00),
    Color(0xFFF9A825),
    Color(0xFF546E7A),
  ];

  @override
  Widget build(BuildContext context) {
    final cats = report.categories;
    return RepaintBoundary(
      child: Semantics(
        container: true,
        label:
            'Spending by category, total '
            '${Money(report.totals.spentMinor, report.currency).format()}',
        child: SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final index =
                          response?.touchedSection?.touchedSectionIndex;
                      if (index == null || index < 0 || index >= cats.length) {
                        return;
                      }
                      onTapCategory(cats[index]);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < cats.length; i++)
                      PieChartSectionData(
                        value: cats[i].shareBp.toDouble(),
                        color: _palette[i % _palette.length],
                        radius: 52,
                        title: '',
                      ),
                  ],
                ),
                // 200 ms cap (§2.4); data reloads rebuild the future, not a
                // re-animated chart, so this only plays on first paint.
                duration: const Duration(milliseconds: 200),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Spent', style: Tokens.labelCaps(context)),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    Money(report.totals.spentMinor, report.currency).format(),
                    key: const Key('donut-total'),
                    style: Tokens.amount(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Month start of the shared 2000-based index grid (mirrors the ledger's).
DateTime _monthStart(int index) => DateTime(2000 + index ~/ 12, index % 12 + 1);
