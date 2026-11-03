// E7 §2/§5 — the Insights segment: the paid trio's analytics half.
//
// Two widgets guard the flavor rule (§5/§6) at different layers:
// [ProTrioGate] makes every trio surface *absent* (not disabled, not a
// teaser) in a free build, and reports_screen.dart additionally omits the
// segment tab itself. Free-suite tests pin both; the CI import guard pins
// that nothing outside this folder reaches in ungated.
import 'dart:typed_data';

import 'package:budget/budget.dart'
    show DayRange, RangeDelta, RecurringSuggestion;
import 'package:core/core.dart' show Money;
import 'package:data/data.dart' show LedgerRepository, ReportWorkbook;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../flavor.dart';
import '../bills/bill_editor_sheet.dart';
import '../manage/io.dart';
import 'analytics_service.dart';
import 'range_sheet.dart';
import 'report_export_service.dart';
import 'report_pdf.dart';

/// Renders [child] only in the pro flavor (§5: the free build shows no
/// trio affordance at all). Cheap, build-time-ish check re-evaluated per
/// build — [FeatureFlags.proTrio] is a compile-time flavor fact.
class ProTrioGate extends StatelessWidget {
  const ProTrioGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FeatureFlags.proTrio ? child : const SizedBox.shrink();
}

const _letters = 'JFMAMJJASOND';

/// "+12.4%" / "−8.0%" from basis points; the null baseline renders an em
/// dash so the card never lies about a comparison it could not make.
String _deltaLabel(RangeDelta d) {
  final bp = d.deltaBp;
  if (bp == null) return '—';
  final pct = (bp.abs() / 100).toStringAsFixed(1);
  if (bp == 0) return '0.0%';
  return '${bp > 0 ? Tokens.plus : Tokens.minus}$pct%';
}

enum _ReportFormat { pdf, xlsx }

class InsightsView extends StatefulWidget {
  const InsightsView({
    super.key,
    required this.repository,
    this.io = const RealIo(),
  });

  final LedgerRepository repository;

  /// §2.3 exports leave the app through the same file seam Manage's CSV
  /// uses, so widget tests can capture the bytes with an in-memory fake.
  final Io io;

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  late final AnalyticsService _service = AnalyticsService(widget.repository);
  final DateTime _today = DateTime.now();
  late DayRange _range = dayRangeFor(RangePreset.thisMonth, today: _today);
  bool _compare = true;

  /// Merchants the owner already turned into bills this visit — their
  /// suggestion cards retire immediately after the editor closes.
  final Set<String> _converted = <String>{};

  late final ReportExportService _exports = ReportExportService(
    widget.repository,
  );
  bool _exporting = false;

  late Future<InsightsReport> _future = _load();

  Future<InsightsReport> _load() => _service.load(
    range: _range,
    compare: _compare ? _range.shiftedBackYear() : null,
  );

  void _reload(DayRange range) {
    setState(() {
      _range = range;
      _future = _load();
    });
  }

  Future<void> _pickRange() async {
    final picked = await showRangeSheet(
      context,
      today: _today,
      current: _range,
    );
    if (picked != null) _reload(picked);
  }

  Future<void> _createBill(RecurringSuggestion s, InsightsReport r) async {
    final created = await showBillEditor(
      context,
      repository: widget.repository,
      currency: r.currency,
      categories: r.categories,
      // E7 §2.2: the suggestion fills the editor; the tap that saves is
      // the owner's, always.
      prefill: BillPrefill(name: s.merchantName, amountMinor: s.amountAvgMinor),
    );
    if (created == true) _converted.add(s.merchantName);
  }

  /// §2.3 — build the on-screen range as a PDF or an Excel workbook and
  /// hand the bytes to the OS share sheet; nothing ever leaves through a
  /// network call, and the free flavor never reaches this code (gated).
  Future<void> _exportReport(InsightsReport r) async {
    final choice = await showModalBottomSheet<_ReportFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('export-pdf'),
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF report'),
              onTap: () => Navigator.pop(context, _ReportFormat.pdf),
            ),
            ListTile(
              key: const Key('export-xlsx'),
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Excel workbook'),
              onTap: () => Navigator.pop(context, _ReportFormat.xlsx),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final data = await _exports.build(r);
      final now = DateTime.now();
      final Uint8List bytes;
      final String name;
      if (choice == _ReportFormat.pdf) {
        bytes = await ReportPdf.build(data);
        name = ReportPdf.fileName(now);
      } else {
        bytes = ReportWorkbook.encode(data);
        name = ReportWorkbook.fileName(now);
      }
      await widget.io.shareFile(bytes: bytes, fileName: name);
      if (mounted) {
        _snack(
          choice == _ReportFormat.pdf
              ? 'PDF report ready to share as $name'
              : 'Excel workbook ready to share as $name',
        );
      }
    } catch (e) {
      if (mounted) _snack('That did not work: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<InsightsReport>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = snap.data!;
        final suggestions = r.suggestions.where(
          (s) => !_converted.contains(s.merchantName),
        );
        return ListView(
          padding: const EdgeInsets.all(Tokens.space4),
          children: [
            Row(
              children: [
                ActionChip(
                  key: const Key('range-chip'),
                  avatar: const Icon(Icons.calendar_today, size: 16),
                  label: Text(formatRangeLabel(r.range)),
                  onPressed: _pickRange,
                ),
                const Spacer(),
                // §2.1: year-over-year comparison is opt-out.
                Switch(
                  key: const Key('compare-switch'),
                  value: _compare,
                  onChanged: (v) => setState(() {
                    _compare = v;
                    _future = _load();
                  }),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            if (r.delta != null)
              Card(
                key: const Key('delta-card'),
                child: Padding(
                  padding: const EdgeInsets.all(Tokens.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spent', style: Tokens.labelCaps(context)),
                      Text(
                        Money(r.totals.spentMinor, r.currency).format(),
                        style: Tokens.amount(
                          context,
                          size: Tokens.monthLabelSize,
                        ),
                      ),
                      const SizedBox(height: Tokens.space2),
                      Text(
                        '${_deltaLabel(r.delta!)} vs '
                        '${formatRangeLabel(r.compare!)}',
                        style: Tokens.body(context),
                      ),
                      if (r.delta!.baseDays != r.delta!.compareDays)
                        // The engine scaled unequal month lengths before
                        // subtracting; the card says so (§2.1 honesty).
                        Text(
                          'normalized ${r.delta!.baseDays} d vs '
                          '${r.delta!.compareDays} d',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Tokens.space3),
            _TrendChart(report: r),
            const SizedBox(height: Tokens.space4),
            Text('Steady monthly charges', style: Tokens.labelCaps(context)),
            const SizedBox(height: Tokens.space2),
            if (suggestions.isEmpty)
              Text(
                'No steady monthly charges in this range.',
                style: Tokens.body(context),
              ),
            for (var i = 0; i < r.suggestions.length; i++)
              if (!_converted.contains(r.suggestions[i].merchantName))
                Card(
                  key: Key('recurring-$i'),
                  margin: const EdgeInsets.only(bottom: Tokens.space2),
                  child: ListTile(
                    leading: const Icon(Icons.autorenew),
                    title: Text(r.suggestions[i].merchantName),
                    subtitle: Text(_suggestionSubtitle(r.suggestions[i], r)),
                    trailing: TextButton(
                      key: Key('create-bill-$i'),
                      onPressed: () => _createBill(r.suggestions[i], r),
                      child: const Text('Create bill'),
                    ),
                  ),
                ),
            const SizedBox(height: Tokens.space3),
            Text(
              'Suggestions only — nothing is ever created without a tap '
              '(§2.2).',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Tokens.space3),
            // §2.3: the free build never shows this row — a gate, not a
            // teaser, exactly like the rest of the trio.
            ProTrioGate(
              child: ListTile(
                key: const Key('export-report'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ios_share),
                title: const Text('Export report'),
                subtitle: const Text('PDF or Excel workbook — stays on device'),
                enabled: !_exporting,
                onTap: _exporting ? null : () => _exportReport(r),
              ),
            ),
            const SizedBox(height: Tokens.space5),
          ],
        );
      },
    );
  }
}

String _suggestionSubtitle(RecurringSuggestion s, InsightsReport r) =>
    '≈ ${Money(s.amountAvgMinor, r.currency).format()} · '
    'every ${s.cadenceDays} d · ${s.hits} hits · '
    '±${(s.amountCoVbp / 100).round()}% spread';

/// Base months as primary rods; the compare year rides beside each as a
/// faded rod (§2.1). Same chart idiom as the Year segment.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.report});

  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buckets = report.buckets;
    if (buckets.isEmpty) {
      return const SizedBox(height: 190);
    }
    final compare = report.compareBuckets.length == buckets.length
        ? report.compareBuckets
        : const <Never>[];
    var maxMinor = 0;
    for (final b in buckets) {
      maxMinor = b.spentMinor > maxMinor ? b.spentMinor : maxMinor;
    }
    for (final b in compare) {
      maxMinor = b.spentMinor > maxMinor ? b.spentMinor : maxMinor;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space3,
          Tokens.space4,
          Tokens.space3,
          Tokens.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              formatRangeLabel(report.range),
              style: Tokens.labelCaps(context),
            ),
            const SizedBox(height: Tokens.space2),
            SizedBox(
              height: 170,
              child: RepaintBoundary(
                child: BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: (maxMinor == 0 ? 1 : maxMinor) * 1.15,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: [
                      for (var i = 0; i < buckets.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: buckets[i].spentMinor.toDouble(),
                              color: scheme.primary,
                              width: compare.isEmpty ? 18 : 11,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                            if (compare.isNotEmpty)
                              BarChartRodData(
                                toY: compare[i].spentMinor.toDouble(),
                                color: scheme.secondary.withValues(alpha: 0.35),
                                width: 11,
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
            Row(
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Text(
                      _letters[int.parse(b.yearMonth.substring(5, 7)) - 1],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (report.compare != null) ...[
              const SizedBox(height: Tokens.space1),
              Text(
                'faded: ${formatRangeLabel(report.compare!)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
