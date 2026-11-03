// E7 §2.1 — the Insights segment's data seam. The engine owns the math
// (packages/budget: DayRange, rangeTotals/rangeBuckets/compareRanges,
// RecurringDetector); this file only adapts repository rows to engine rows
// through the *same* ReportsService mapping the Reports screen uses — one
// exclusion-rule set, one truth.
//
// Flavor-neutral on purpose: the class compiles into every flavor and its
// tests run in the free CI suite — the math is not a paid feature, only
// its surfacing is (see ProTrioGate in insights_view.dart and the import
// grep guard in the app-test CI job).
import 'dart:math' as math;

import 'package:budget/budget.dart';
import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';

import '../reports/reports_service.dart';

/// What the range sheet offers (E7 §2.1: "presets plus custom dates").
enum RangePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  thisYear('This year'),
  lastYear('Last year');

  const RangePreset(this.label);
  final String label;
}

/// The preset's [DayRange] against a civil *today* — closed-open like every
/// engine period. Local calendar components only (dayOf drops the clock),
/// so a device time zone never shifts a month boundary.
DayRange dayRangeFor(RangePreset preset, {required DateTime today}) {
  final y = today.year;
  final m = today.month;
  return switch (preset) {
    RangePreset.thisMonth => DayRange(
      startDay: dayOf(DateTime.utc(y, m)),
      endDay: dayOf(DateTime.utc(y, m + 1)),
    ),
    RangePreset.lastMonth => DayRange(
      startDay: dayOf(DateTime.utc(y, m - 1)),
      endDay: dayOf(DateTime.utc(y, m)),
    ),
    RangePreset.thisYear => DayRange(
      startDay: dayOf(DateTime.utc(y)),
      endDay: dayOf(DateTime.utc(y + 1)),
    ),
    RangePreset.lastYear => DayRange(
      startDay: dayOf(DateTime.utc(y - 1)),
      endDay: dayOf(DateTime.utc(y)),
    ),
  };
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact human label for a range: whole month → "Mar 2026", whole year →
/// "2026", anything else the day span. Only the delta card and the chip
/// need names this short; nothing here is a data format.
String formatRangeLabel(DayRange r) {
  final s = DateTime.utc(1970).add(Duration(days: r.startDay));
  final e = DateTime.utc(1970).add(Duration(days: r.endDay - 1));
  final wholeMonth =
      s.month == e.month &&
      s.year == e.year &&
      s.day == 1 &&
      e.day == DateTime.utc(s.year, s.month + 1, 0).day;
  if (wholeMonth) return '${_shortMonths[s.month - 1]} ${s.year}';
  final wholeYear =
      s.month == 1 &&
      s.day == 1 &&
      e.month == 12 &&
      e.day == 31 &&
      s.year == e.year;
  if (wholeYear) return '${s.year}';
  if (s.year != e.year) {
    return '${_shortMonths[s.month - 1]} ${s.day}, ${s.year} – '
        '${_shortMonths[e.month - 1]} ${e.day}, ${e.year}';
  }
  return '${_shortMonths[s.month - 1]} ${s.day} – '
      '${_shortMonths[e.month - 1]} ${e.day}, ${s.year}';
}

/// One fully-computed Insights load. Widgets render this; they never sum.
final class InsightsReport {
  const InsightsReport({
    required this.range,
    required this.compare,
    required this.currency,
    required this.totals,
    required this.buckets,
    required this.compareBuckets,
    required this.delta,
    required this.suggestions,
    required this.categories,
  });

  final DayRange range;

  /// The YoY compare range when the toggle is on, else null.
  final DayRange? compare;

  final Currency currency;
  final MonthTotals totals;

  /// Base spend per touched calendar month, chronological, zeros included.
  final List<MonthBucket> buckets;

  /// Compare-side buckets, index-aligned with [buckets] when set (the
  /// year shift preserves the month count by construction).
  final List<MonthBucket> compareBuckets;

  /// Null whenever [compare] is — the delta card only exists with a
  /// comparison.
  final RangeDelta? delta;

  /// E7 §2.2 detector output over the base range's rows — suggestions only,
  /// never applied automatically.
  final List<RecurringSuggestion> suggestions;

  /// Carried for the one-tap bill editor (the sheet wants them, and the
  /// view should not re-query mid-tap).
  final List<Category> categories;
}

class AnalyticsService {
  AnalyticsService(this._repo) : _reports = ReportsService(_repo);

  final LedgerRepository _repo;
  final ReportsService _reports;

  static const _engine = ReportEngine();

  /// Loads rows once over the union of base and compare windows, then lets
  /// the engine slice them — same pattern as [ReportsService.loadMonth].
  Future<InsightsReport> load({
    required DayRange range,
    DayRange? compare,
  }) async {
    final base = Currency.resolve(await _repo.baseCurrency() ?? 'USD');
    var from = range.startDay;
    var to = range.endDay - 1;
    if (compare != null) {
      from = math.min(from, compare.startDay);
      to = math.max(to, compare.endDay - 1);
    }
    final rows = await _reports.engineRows(from, to, base);
    final inRange = [
      for (final t in rows)
        if (range.contains(t.dateDays)) t,
    ];
    return InsightsReport(
      range: range,
      compare: compare,
      currency: base,
      totals: _engine.rangeTotals(range, rows),
      buckets: _engine.rangeBuckets(range, rows),
      compareBuckets: compare == null
          ? const []
          : _engine.rangeBuckets(compare, rows),
      delta: compare == null
          ? null
          : _engine.compareRanges(range, compare, rows),
      suggestions: RecurringDetector.suggest(inRange),
      categories: await _repo.categories(),
    );
  }
}
