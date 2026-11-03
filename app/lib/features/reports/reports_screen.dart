import 'package:budget/budget.dart' show BudgetStatus, CategoryTotal;
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../flavor.dart';
import '../analytics/insights_view.dart';
import '../budgets/budgets_service.dart';
import '../budgets/budgets_sheet.dart';
import '../ledger/ledger_screen.dart' show monthIndexOf, monthTitle, tileFor;
import '../ledger/transaction_row.dart';
import '../manage/icon_registry.dart';
import 'reports_service.dart';

/// The three analytics surfaces (§1) — the segmented control's values.
enum ReportSegment {
  month('Month'),
  year('Year'),
  actual('Actual'),
  insights('Insights');

  const ReportSegment(this.label);
  final String label;
}

/// The Reports screen (E4 spec §2). Month is the default segment (§2.1);
/// Year shows twelve expense bars plus the year's top categories (§2.2);
/// Actual renders the Budgets tab's own statuses as bar-vs-marker rows
/// (§2.3). B4 ships all three on the scaffold B3 built.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    this.initialSegment = ReportSegment.month,
  });

  final LedgerRepository repository;

  /// Entrance 2 (§1): the Budgets sheet opens Reports on [actual].
  final ReportSegment initialSegment;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsService _service = ReportsService(widget.repository);
  late final BudgetsService _budgets = BudgetsService(widget.repository);

  /// Index of the visible month in the shared 2000-based calendar grid.
  int _monthIndex = monthIndexOf(DateTime.now());
  late Future<MonthReport> _report = _load();

  late ReportSegment _segment = widget.initialSegment;

  /// Calendar year of the Year segment (§2.2) — absolute, not grid-indexed.
  late int _year = DateTime.now().year;

  /// Year and Actual load lazily — opening a segment pays for its queries,
  /// and switching back shows the same finished snapshot, not a spinner.
  Future<YearReport>? _yearReport;
  Future<BudgetsSnapshot>? _actual;

  @override
  void initState() {
    super.initState();
    // The laziness above must not strand the ENTRANCE segment (§1: the
    // Budgets sheet lands on actual) — prime whatever we open on.
    if (widget.initialSegment == ReportSegment.year) _yearReport = _loadYear();
    if (widget.initialSegment == ReportSegment.actual) _actual = _loadActual();
  }

  Future<MonthReport> _load() => _service.loadMonth(_monthStart(_monthIndex));
  Future<YearReport> _loadYear() => _service.loadYear(_year);
  Future<BudgetsSnapshot> _loadActual() => _budgets.load(_monthIndex);

  void _select(ReportSegment segment) {
    setState(() {
      _segment = segment;
      if (segment == ReportSegment.year) _yearReport ??= _loadYear();
      if (segment == ReportSegment.actual) _actual ??= _loadActual();
    });
  }

  /// Shifts the month stepper (Month and Actual segments share it);
  /// `+1` is unreachable from the current month (the button is disabled —
  /// the future is not navigable, §2.1).
  void _shift(int delta) {
    setState(() {
      _monthIndex += delta;
      _report = _load();
      if (_actual != null) _actual = _loadActual();
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      _year += delta;
      _yearReport = _loadYear();
    });
  }

  /// A bar tap jumps the Month segment to that month (§2.2 state handoff).
  void _openMonth(int year, int month0) {
    setState(() {
      _monthIndex = monthIndexOf(DateTime(year, month0 + 1));
      _segment = ReportSegment.month;
      _report = _load();
    });
  }

  /// Empty-state CTA (§2.3): pop this page and open the Budgets sheet the
  /// user actually needs — one gesture from "no budgets" to setting limits.
  void _openBudgets() {
    final context = this.context;
    Navigator.of(context).pop();
    showBudgetsSheet(
      context,
      repository: widget.repository,
      monthIndex: _monthIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowIndex = monthIndexOf(DateTime.now());
    final nowYear = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space4,
                0,
                Tokens.space4,
                Tokens.space1,
              ),
              child: SegmentedButton<ReportSegment>(
                segments: [
                  for (final s in ReportSegment.values)
                    // E7 §5: a free build shows no trio affordance — the
                    // gate inside only hides the content, so the segment
                    // itself is filtered here too.
                    if (s != ReportSegment.insights || FeatureFlags.proTrio)
                      ButtonSegment(
                        value: s,
                        // ButtonSegment carries no key of its own — the label
                        // is the widget; keys ride there for tests & e2e.
                        label: Text(s.label, key: Key('segment-${s.name}')),
                      ),
                ],
                selected: {_segment},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _select(s.first),
              ),
            ),
            if (_segment == ReportSegment.year)
              _Stepper(
                title: '$_year',
                prevKey: const Key('year-prev'),
                nextKey: const Key('year-next'),
                prevTooltip: 'Previous year',
                nextTooltip: 'Next year',
                canGoNext: _year < nowYear,
                onPrev: () => _shiftYear(-1),
                onNext: () => _shiftYear(1),
              )
            else if (_segment != ReportSegment.insights)
              // Insights carries its own range chip (§2.1); a month stepper
              // next to it would be two truths about the same window.
              _Stepper(
                title: monthTitle(_monthIndex),
                prevKey: const Key('month-prev'),
                nextKey: const Key('month-next'),
                prevTooltip: 'Previous month',
                nextTooltip: 'Next month',
                canGoNext: _monthIndex < nowIndex,
                onPrev: () => _shift(-1),
                onNext: () => _shift(1),
              ),
            Expanded(
              // 200 ms fade-through between segments (§6) — data reloads
              // inside a segment swap futures, not the switcher's child.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (_segment) {
                  ReportSegment.month => FutureBuilder<MonthReport>(
                    key: const ValueKey(ReportSegment.month),
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
                  ReportSegment.year => FutureBuilder<YearReport>(
                    key: const ValueKey(ReportSegment.year),
                    future: _yearReport,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _LoadError(
                          onRetry: () =>
                              setState(() => _yearReport = _loadYear()),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _YearView(
                        report: snap.data!,
                        onPickMonth: _openMonth,
                      );
                    },
                  ),
                  ReportSegment.actual => FutureBuilder<BudgetsSnapshot>(
                    key: const ValueKey(ReportSegment.actual),
                    future: _actual,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _LoadError(
                          onRetry: () =>
                              setState(() => _actual = _loadActual()),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _ActualView(
                        snapshot: snap.data!,
                        onSetBudgets: _openBudgets,
                      );
                    },
                  ),
                  ReportSegment.insights => ProTrioGate(
                    key: const ValueKey(ReportSegment.insights),
                    child: InsightsView(repository: widget.repository),
                  ),
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
    required this.prevKey,
    required this.nextKey,
    required this.prevTooltip,
    required this.nextTooltip,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final Key prevKey;
  final Key nextKey;
  final String prevTooltip;
  final String nextTooltip;
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
            key: prevKey,
            tooltip: prevTooltip,
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
            key: nextKey,
            tooltip: nextTooltip,
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
                baseCode: report.currency.code,
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
    required this.baseCode,
  });

  final LedgerRepository repository;
  final String yearMonth;
  final int categoryId;

  /// Device base — lets a "No rate" row whisper here too (E5 §6).
  final String baseCode;

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
          children: [
            for (final r in rows)
              TransactionRow(tile: tileFor(r, baseCode: widget.baseCode)),
          ],
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
              // §6: fl_chart tooltips are pointer-only, so TalkBack gets
              // each slice as its own row of this section — "Food, 42%,
              // $212.10". The nodes paint nothing; the expand child gives
              // each one a real rect so traversal keeps it, and
              // container:true stops it merging into the section label.
              for (var i = 0; i < cats.length; i++)
                Positioned.fill(
                  child: Semantics(
                    key: Key('donut-slice-${cats[i].categoryId}'),
                    container: true,
                    label:
                        '${report.categoryNames[cats[i].categoryId] ?? 'Uncategorized'}'
                        ', ${Money(cats[i].spentMinor, report.currency).format()}'
                        ', ${(cats[i].shareBp / 100).round()}%',
                    excludeSemantics: true,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Year segment (§2.2): twelve expense bars with a year-average line, then
/// the year's top five categories. A bar tap hands the Month segment that
/// month — the screen swaps segments in place, no second route.
class _YearView extends StatelessWidget {
  const _YearView({required this.report, required this.onPickMonth});

  final YearReport report;
  final void Function(int year, int month0) onPickMonth;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June', //
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = report;
    var maxMinor = r.averageMinor;
    for (final b in r.buckets) {
      if (b.spentMinor > maxMinor) maxMinor = b.spentMinor;
    }
    if (maxMinor <= 0) maxMinor = 1;
    // §6: the bars read as a table to TalkBack — "November, $1,204.00".
    final spoken = [
      for (var i = 0; i < 12; i++)
        if (r.buckets[i].spentMinor > 0)
          '${_monthNames[i]}, ${Money(r.buckets[i].spentMinor, r.currency).format()}',
    ];

    return ListView(
      padding: const EdgeInsets.all(Tokens.space4),
      children: [
        _SectionCard(
          title: 'Monthly spending',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total ${Money(r.totalSpentMinor, r.currency).format()}'
                '  ·  ${Money(r.averageMinor, r.currency).format()} avg',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Tokens.space3),
              Semantics(
                key: const Key('year-bars'),
                container: true,
                label: spoken.isEmpty
                    ? 'No spending in ${r.year}.'
                    : '${r.year}: ${spoken.join('; ')}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    SizedBox(
                      height: 190,
                      child: RepaintBoundary(
                        child: BarChart(
                          BarChartData(
                            minY: 0,
                            maxY: maxMinor * 1.15,
                            alignment: BarChartAlignment.spaceAround,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            // The average is drawn, not just meant (§2.2).
                            extraLinesData: r.averageMinor > 0
                                ? ExtraLinesData(
                                    horizontalLines: [
                                      HorizontalLine(
                                        y: r.averageMinor.toDouble(),
                                        color: scheme.onSurfaceVariant,
                                        strokeWidth: 1,
                                        dashArray: const [4, 4],
                                      ),
                                    ],
                                  )
                                : const ExtraLinesData(),
                            barTouchData: BarTouchData(
                              touchCallback: (event, response) {
                                if (event is! FlTapUpEvent) return;
                                final idx =
                                    response?.spot?.touchedBarGroupIndex;
                                if (idx == null || idx < 0 || idx > 11) return;
                                onPickMonth(r.year, idx);
                              },
                            ),
                            barGroups: [
                              for (var i = 0; i < 12; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: r.buckets[i].spentMinor.toDouble(),
                                      // The current month gets the accent
                                      // shade; complete months stay primary.
                                      color: r.isCurrent && i == r.currentMonth
                                          ? scheme.secondary
                                          : scheme.primary,
                                      width: 18,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(3),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          duration: const Duration(milliseconds: 200),
                        ),
                      ),
                    ),
                    const SizedBox(height: Tokens.space1),
                    // Month letters below the bars — the only axis v1 needs.
                    Row(
                      children: [
                        for (var i = 0; i < 12; i++)
                          Expanded(
                            child: Text(
                              _monthNames[i][0],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.space3),
        _SectionCard(
          title: 'Top categories',
          child: r.topCategories.isEmpty
              ? _EmptyNote(
                  key: const Key('year-cats-empty'),
                  text: 'Nothing spent in ${r.year}.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < r.topCategories.length; i++)
                      _CategoryShareRow(
                        index: i,
                        total: r.topCategories[i],
                        name:
                            r.categoryNames[r.topCategories[i].categoryId] ??
                            '—',
                        currency: r.currency,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One top-5 row: name + money on one line, the share-of-year bar below.
class _CategoryShareRow extends StatelessWidget {
  const _CategoryShareRow({
    required this.index,
    required this.total,
    required this.name,
    required this.currency,
  });

  final int index;
  final CategoryTotal total;
  final String name;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = Money(total.spentMinor, currency).format();
    final pct = total.shareBp / 100;
    final fraction = (total.shareBp / 10000).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      child: Semantics(
        label: '$name, $money, ${pct.toStringAsFixed(0)}% of the year',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(context),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Text(
                  money,
                  style: Tokens.amount(context).copyWith(fontSize: 13),
                ),
                const SizedBox(width: Tokens.space2),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${pct.toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space1),
            SizedBox(
              height: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: ColoredBox(
                    color: _Donut._palette[index % _Donut._palette.length],
                    child: const SizedBox(height: 8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Budget-vs-actual segment (§2.3). The *statuses* are the Budgets tab's own
/// `BudgetsService.load` snapshot — this view only re-paints them as bar +
/// marker rows, so the two surfaces can never disagree (§2.3 single source).
class _ActualView extends StatelessWidget {
  const _ActualView({required this.snapshot, required this.onSetBudgets});

  final BudgetsSnapshot snapshot;
  final VoidCallback onSetBudgets;

  @override
  Widget build(BuildContext context) {
    final overall = snapshot.overall;
    // Zero-limit rows are placeholders in the editor; analytics hides them.
    final rows = snapshot.lines
        .where((l) => l.row.limitMinor > 0)
        .toList(growable: false);
    if (overall == null && rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _EmptyNote(
              key: Key('actual-empty'),
              text: 'No budgets yet — set limits to compare.',
            ),
            const SizedBox(height: Tokens.space3),
            FilledButton.tonal(
              key: const Key('actual-open-budgets'),
              onPressed: onSetBudgets,
              child: const Text('Set budgets'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      children: [
        if (overall != null)
          _ActualRow(
            key: const Key('actual-overall'),
            keySuffix: 'overall',
            label: 'All categories',
            status: overall,
            currency: snapshot.currency,
            rollover: snapshot.rollover,
          ),
        for (final line in rows)
          _ActualRow(
            key: Key('actual-row-${line.row.categoryId ?? line.row.id}'),
            keySuffix: '${line.row.categoryId ?? line.row.id}',
            label: line.name,
            status: line.status,
            currency: snapshot.currency,
            rollover: snapshot.rollover,
          ),
      ],
    );
  }
}

/// Bar = spent, solid marker = limit, ghost marker = carry-adjusted
/// available — the ghost only when the device-wide rollover switch is on
/// (§2.3). Colors are the Budgets tab's one expression, copied literally.
class _ActualRow extends StatelessWidget {
  const _ActualRow({
    super.key,
    required this.keySuffix,
    required this.label,
    required this.status,
    required this.currency,
    required this.rollover,
  });

  /// Shared suffix for the row's marker/ghost keys (`Key` carries no value
  /// to derive it from at paint time).
  final String keySuffix;
  final String label;
  final BudgetStatus status;
  final Currency currency;
  final bool rollover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overspent = status.isOverspent;
    final barColor = overspent ? scheme.error : scheme.primary;
    final spent = status.spent(currency).format();
    final limit = Money(status.effectiveLimitMinor, currency).format();
    var scale = 1;
    for (final v in [
      status.spentMinor,
      status.limitMinor,
      status.effectiveLimitMinor,
    ]) {
      if (v > scale) scale = v;
    }
    final showGhost = rollover && status.carryMinor != 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space4,
        vertical: Tokens.space3,
      ),
      child: Semantics(
        key: Key('actual-semantics-$keySuffix'),
        label: '$spent of $limit for $label',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, track) => Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(context),
                    ),
                  ),
                  // Non-flex so a fitting amount sizes and places itself
                  // exactly like a plain Text (golden refs pin this
                  // geometry); the cap only lets 1.3× text scale wrap it
                  // instead of overflowing, once the label keeps 88 dp.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (track.maxWidth - 88).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: Text(
                      'Spent $spent of $limit',
                      style: TextStyle(
                        fontSize: 12,
                        color: overspent
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Tokens.space2),
            SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, track) {
                  final w = track.maxWidth;
                  Widget marker(double fraction, Color color, {Key? key}) {
                    return Positioned(
                      key: key,
                      left: (fraction * w - 1).clamp(0.0, w - 2),
                      child: Container(width: 2, height: 12, color: color),
                    );
                  }

                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (status.spentMinor / scale).clamp(
                            0.0,
                            1.0,
                          ),
                          child: Container(height: 8, color: barColor),
                        ),
                      ),
                      // Solid tick where the limit sits; the ghost shows the
                      // carry-adjusted available next to it (rollover on).
                      marker(
                        status.limitMinor / scale,
                        scheme.onSurface,
                        key: Key('actual-marker-$keySuffix'),
                      ),
                      if (showGhost)
                        marker(
                          status.effectiveLimitMinor / scale,
                          scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          key: Key('actual-ghost-$keySuffix'),
                        ),
                    ],
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

/// Month start of the shared 2000-based index grid (mirrors the ledger's).
DateTime _monthStart(int index) => DateTime(2000 + index ~/ 12, index % 12 + 1);
