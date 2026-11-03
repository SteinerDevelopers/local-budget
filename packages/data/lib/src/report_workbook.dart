/// E7 spec §2.3 — the analytics report as an Excel workbook: sheets
/// Summary / Months / Categories / Transactions, in that order.
///
/// This is a pure model + renderer: the app's export service loads the same
/// ledger rows the free CSV reads and the engine already summed, and hands
/// the plain values here. Amounts are base-currency minor units everywhere
/// except [ReportTxnRow], which keeps the row's own currency exactly like
/// the CSV does.
library;

import 'dart:typed_data';

import 'package:core/core.dart' show Currency;

import 'export_csv.dart' show CsvExport;
import 'xlsx.dart';

/// One Months-sheet bucket; [compareSpentMinor] is the year-shifted
/// compare-side value when the report was loaded with a comparison.
final class ReportMonthRow {
  const ReportMonthRow({
    required this.yearMonth,
    required this.spentMinor,
    this.compareSpentMinor,
  });

  final String yearMonth;
  final int spentMinor;
  final int? compareSpentMinor;
}

/// One Categories-sheet row — [shareBp] is the engine's per-category share
/// of the category total (basis points).
final class ReportCategoryRow {
  const ReportCategoryRow({
    required this.name,
    required this.spentMinor,
    required this.shareBp,
  });

  final String name;
  final int spentMinor;
  final int shareBp;
}

/// One ledger row on the Transactions sheet — the CSV's own columns.
/// Amount is unsigned storage + the income flag, the same convention the
/// transactions table uses; the bank sign appears at render time only.
final class ReportTxnRow {
  const ReportTxnRow({
    required this.date,
    required this.description,
    required this.category,
    required this.note,
    required this.amountMinor,
    required this.isIncome,
    required this.currencyCode,
    required this.account,
  });

  final DateTime date;
  final String description;
  final String category;
  final String note;
  final int amountMinor;
  final bool isIncome;
  final String currencyCode;
  final String account;
}

/// The on-screen Insights load as plain values — what the widgets render,
/// minus widgets. Minor units and ints throughout (spec §1 money rule).
final class ReportData {
  const ReportData({
    required this.rangeLabel,
    required this.generatedAt,
    required this.currency,
    required this.spentMinor,
    required this.incomeMinor,
    required this.netMinor,
    this.compareLabel,
    this.compareSpentMinor,
    this.compareNormalizedMinor,
    this.deltaBp,
    this.months = const [],
    this.categories = const [],
    this.transactions = const [],
  });

  final String rangeLabel;
  final DateTime generatedAt;
  final Currency currency;
  final int spentMinor;
  final int incomeMinor;
  final int netMinor;

  /// Comparison block — all null together when the toggle was off.
  final String? compareLabel;
  final int? compareSpentMinor;
  final int? compareNormalizedMinor;
  final int? deltaBp;

  final List<ReportMonthRow> months;
  final List<ReportCategoryRow> categories;
  final List<ReportTxnRow> transactions;
}

/// Renders [ReportData] into the §2.3 workbook.
abstract final class ReportWorkbook {
  /// Share-sheet friendly file name, mirroring [CsvExport.fileName].
  static String fileName(DateTime now) =>
      'budget-report-${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}.xlsx';

  static Uint8List encode(ReportData d) => encodeXlsx(sheets(d));

  /// The four §2.3 sheets in contract order. Money renders as the CSV's
  /// locale-free decimals (currency-exponent digits, no grouping); share
  /// and delta render as percents.
  static List<XlsxSheet> sheets(ReportData d) {
    final cur = d.currency;
    final summary = <List<Object?>>[
      ['Report', 'LocalBudget report'],
      ['Range', d.rangeLabel],
      ['Generated', isoDateTime(d.generatedAt)],
      ['Currency', cur.code],
      ['Spent', decimal(d.spentMinor, cur)],
      ['Income', decimal(d.incomeMinor, cur)],
      ['Net', decimal(d.netMinor, cur)],
      if (d.compareLabel != null) ['Compare range', d.compareLabel],
      if (d.compareSpentMinor != null)
        ['Compare spent', decimal(d.compareSpentMinor!, cur)],
      if (d.compareNormalizedMinor != null)
        ['Compare spent (normalized)', decimal(d.compareNormalizedMinor!, cur)],
      if (d.deltaBp != null)
        ['Change', '${d.deltaBp! >= 0 ? '+' : ''}${percent(d.deltaBp! / 100)}'],
    ];

    final showCompare = d.months.any((m) => m.compareSpentMinor != null);
    final months = <List<Object?>>[
      ['Month', 'Spent', if (showCompare) 'Spent (compare)'],
      for (final m in d.months)
        [
          m.yearMonth,
          decimal(m.spentMinor, cur),
          if (showCompare)
            m.compareSpentMinor == null
                ? ''
                : decimal(m.compareSpentMinor!, cur),
        ],
    ];

    final categories = <List<Object?>>[
      ['Category', 'Spent', 'Share'],
      for (final c in d.categories)
        [c.name, decimal(c.spentMinor, cur), percent(c.shareBp / 100)],
    ];

    final transactions = <List<Object?>>[
      CsvExport.header,
      for (final t in d.transactions)
        [
          isoDate(t.date),
          t.description,
          t.category,
          t.note,
          CsvExport.signedDecimal(t.amountMinor, t.isIncome, t.currencyCode),
          t.currencyCode,
          t.account,
        ],
    ];

    return [
      XlsxSheet('Summary', rows: summary),
      XlsxSheet('Months', rows: months),
      XlsxSheet('Categories', rows: categories),
      XlsxSheet('Transactions', rows: transactions),
    ];
  }

  /// Signed, exponent-exact decimal for base-currency totals (net can go
  /// negative; the magnitude path is the CSV's).
  static String decimal(int minor, Currency cur) => minor < 0
      ? '-${CsvExport.decimal(minor, cur.code)}'
      : CsvExport.decimal(minor, cur.code);

  static String percent(double pct) => '${pct.toStringAsFixed(1)}%';
}

/// 'YYYY-MM-DD' — the file date format, same shape the CSV uses.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 'YYYY-MM-DDTHH:MM' — civil time, no zone games (the file records the
/// device's clock, like every other timestamp in the app).
String isoDateTime(DateTime d) =>
    '${isoDate(d)}T'
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
