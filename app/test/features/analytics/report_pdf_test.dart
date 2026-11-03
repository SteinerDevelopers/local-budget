// E7 §2.3 — the PDF half of the export trio, rendered from a plain
// ReportData: real bytes off the pure-Dart pipeline, no platform channel,
// so the CI host proves "it is a PDF" without a printer or a browser.
import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/analytics/report_pdf.dart';

ReportData fixture() => ReportData(
  rangeLabel: '01 Mar 2026 – 31 Mar 2026',
  generatedAt: DateTime(2026, 4, 1, 8, 30),
  currency: Currency.resolve('USD'),
  spentMinor: 1854300,
  incomeMinor: 3200000,
  netMinor: 1345700,
  compareLabel: '01 Mar 2025 – 31 Mar 2025',
  compareSpentMinor: 1940000,
  compareNormalizedMinor: 1930000,
  deltaBp: -427,
  months: [
    for (var m = 1; m <= 12; m++)
      ReportMonthRow(
        yearMonth: '2026-${m.toString().padLeft(2, '0')}',
        spentMinor: 100000 + m * 7777,
        compareSpentMinor: 90000 + m * 6000,
      ),
  ],
  categories: [
    for (var c = 0; c < 10; c++)
      ReportCategoryRow(
        name: c == 3 ? 'Café & "Sons" <x>' : 'Category $c',
        spentMinor: 200000 - c * 15000,
        shareBp: 1538 - c * 100,
      ),
  ],
  transactions: [
    for (var t = 0; t < 50; t++)
      ReportTxnRow(
        date: DateTime(2026, 3, 1 + t % 28),
        description: 'Merchant $t',
        category: 'Category ${t % 10}',
        note: '',
        amountMinor: 1234 + t * 99,
        isIncome: false,
        currencyCode: 'USD',
        account: 'Cash',
      ),
  ],
);

void main() {
  test('the report renders as a real multi-kilobyte PDF', () async {
    final bytes = await ReportPdf.build(fixture());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(2000));
    expect(
      String.fromCharCodes(bytes.skip(bytes.lengthInBytes - 10)),
      contains('%%EOF'),
    );
  });

  test('an empty ledger still produces a PDF', () async {
    final bytes = await ReportPdf.build(
      ReportData(
        rangeLabel: 'Nov 2026',
        generatedAt: DateTime(2026, 12, 1),
        currency: Currency.resolve('JPY'),
        spentMinor: 0,
        incomeMinor: 0,
        netMinor: 0,
      ),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('deterministic title and a date-stamped file name', () async {
    expect(ReportPdf.title, 'LocalBudget report');
    expect(
      ReportPdf.fileName(DateTime(2026, 3, 7)),
      'budget-report-2026-03-07.pdf',
    );
  });
}
