// E7 §2.3 — the §2.3 exports' single load. The Insights widgets show
// aggregates; the PDF and the workbook print them, so this takes the very
// InsightsReport already on screen and adds only what the sheets need:
// range-scoped category totals and the ledger rows under the CSV's own
// column rules. One repository read, two renderers — the exports can never
// disagree with each other or with the screen.
import 'package:budget/budget.dart' show DayRange;
import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';

import '../reports/reports_service.dart';
import 'analytics_service.dart';

/// Assembles the plain [ReportData] model both §2.3 renderers consume.
class ReportExportService {
  ReportExportService(this._repo) : _reports = ReportsService(_repo);

  final LedgerRepository _repo;
  final ReportsService _reports;

  Future<ReportData> build(InsightsReport r, {DateTime? now}) async {
    final base = r.currency;
    final from = r.range.startDay;
    final to = r.range.endDay - 1;
    final delta = r.delta;

    final names = <int, String>{
      for (final c in await _repo.categories()) c.id: c.name,
    };

    return ReportData(
      rangeLabel: formatRangeLabel(r.range),
      generatedAt: now ?? DateTime.now(),
      currency: base,
      spentMinor: r.totals.spentMinor,
      incomeMinor: r.totals.incomeMinor,
      netMinor: r.totals.netMinor,
      compareLabel: r.compare == null ? null : formatRangeLabel(r.compare!),
      compareSpentMinor: delta?.compareSpentMinor,
      compareNormalizedMinor: delta?.compareNormalizedMinor,
      deltaBp: delta?.deltaBp,
      months: [
        for (var i = 0; i < r.buckets.length; i++)
          ReportMonthRow(
            yearMonth: r.buckets[i].yearMonth,
            spentMinor: r.buckets[i].spentMinor,
            compareSpentMinor: i < r.compareBuckets.length
                ? r.compareBuckets[i].spentMinor
                : null,
          ),
      ],
      categories: await _categoryRows(r.range, base, names),
      transactions: await _txnRows(from, to, names),
    );
  }

  /// Category totals over the *range* — [ReportEngine.categoryTotals]
  /// answers for calendar periods only, so this mirrors its exact rules
  /// (budget scope, positive rows, amount-desc then id-asc, truncated
  /// shares whose last row absorbs the residue to 10000 bp) over a
  /// [DayRange] instead of forking the engine's truth elsewhere.
  Future<List<ReportCategoryRow>> _categoryRows(
    DayRange range,
    Currency base,
    Map<int, String> names,
  ) async {
    final rows = await _reports.engineRows(range.startDay, range.endDay - 1, base);
    final byId = <int, int>{};
    for (final t in rows) {
      if (!range.contains(t.dateDays) || !t.countsTowardBudgets) continue;
      byId.update(
        t.categoryId,
        (v) => v + t.baseAmountMinor,
        ifAbsent: () => t.baseAmountMinor,
      );
    }
    final ranked =
        byId.entries.where((e) => e.value > 0).toList()
          ..sort(
            (a, b) => a.value != b.value
                ? b.value.compareTo(a.value)
                : a.key.compareTo(b.key),
          );
    final total = ranked.fold(0, (int s, e) => s + e.value);
    if (total <= 0) return const [];
    final result = <ReportCategoryRow>[];
    var assigned = 0;
    for (var i = 0; i < ranked.length; i++) {
      final share =
          i == ranked.length - 1 ? 10000 - assigned : ranked[i].value * 10000 ~/ total;
      assigned += share;
      result.add(
        ReportCategoryRow(
          name: names[ranked[i].key] ?? 'Uncategorized',
          spentMinor: ranked[i].value,
          shareBp: share,
        ),
      );
    }
    return result;
  }

  /// The base window's ledger rows in the CSV's own shape (§2.3: "the same
  /// ledger data the CSV export uses") — goal transfers already excluded,
  /// merchant-else-note description, unsigned amount + income flag.
  Future<List<ReportTxnRow>> _txnRows(
    int from,
    int to,
    Map<int, String> categoryNames,
  ) async {
    final merchants = await _repo.merchantNames();
    final accounts = {
      for (final a in await _repo.accounts(includeArchived: true))
        a.id: a.name,
    };
    return [
      for (final t in await _repo.transactionsInRange(from, to))
        ReportTxnRow(
          date: dateFromEpochDay(t.dateDays),
          // Same precedence as the CSV: a minted merchant name wins, the
          // note speaks for itself when there is none.
          description: _description(
            t.merchantId == null ? '' : (merchants[t.merchantId!] ?? ''),
            t.note ?? '',
          ),
          category: t.categoryId == null
              ? ''
              : (categoryNames[t.categoryId!] ?? ''),
          note: t.note ?? '',
          amountMinor: t.amountMinor,
          isIncome: t.isIncome,
          currencyCode: t.currencyCode,
          account: accounts[t.accountId] ?? '',
        ),
    ];
  }

  static String _description(String merchant, String note) =>
      merchant.isNotEmpty ? merchant : note;
}
