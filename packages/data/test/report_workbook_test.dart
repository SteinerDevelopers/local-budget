import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';
import 'package:test/test.dart';

Map<String, String> unzip(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in zip.files)
      if (f.isFile) f.name: utf8.decode(f.content),
  };
}

ReportData _data() => ReportData(
  rangeLabel: 'Mar 2026',
  generatedAt: DateTime(2026, 3, 7, 9, 5),
  currency: Currency.resolve('USD'),
  spentMinor: 123456,
  incomeMinor: 100000,
  netMinor: -23456,
  compareLabel: 'Mar 2025',
  compareSpentMinor: 90000,
  compareNormalizedMinor: 92000,
  deltaBp: 1234,
  months: const [
    ReportMonthRow(
      yearMonth: '2026-02',
      spentMinor: 30000,
      compareSpentMinor: 12000,
    ),
    ReportMonthRow(
      yearMonth: '2026-03',
      spentMinor: 93456,
      compareSpentMinor: 78000,
    ),
  ],
  categories: const [
    ReportCategoryRow(name: 'Rent', spentMinor: 60000, shareBp: 6000),
    ReportCategoryRow(name: 'Food', spentMinor: 30000, shareBp: 3000),
    ReportCategoryRow(name: 'Fun', spentMinor: 10000, shareBp: 1000),
  ],
  transactions: [
    ReportTxnRow(
      date: DateTime(2026, 3, 4),
      description: 'Café & "Sons" <x>',
      category: 'Food',
      note: 'team lunch',
      amountMinor: 1234,
      isIncome: false,
      currencyCode: 'USD',
      account: 'Cash',
    ),
    ReportTxnRow(
      date: DateTime(2026, 3, 1),
      description: 'Salary',
      category: 'Salary',
      note: '',
      amountMinor: 200000,
      isIncome: true,
      currencyCode: 'USD',
      account: 'Checking',
    ),
    ReportTxnRow(
      date: DateTime(2026, 3, 2),
      description: 'Konbini',
      category: '',
      note: '',
      amountMinor: 1485,
      isIncome: false,
      currencyCode: 'JPY',
      account: 'Cash',
    ),
  ],
);

void main() {
  group('ReportWorkbook', () {
    late Map<String, String> parts;

    setUp(() => parts = unzip(ReportWorkbook.encode(_data())));

    test('sheets are Summary, Months, Categories, Transactions in order', () {
      expect(
        parts['xl/workbook.xml'],
        contains(
          '<sheet name="Summary" sheetId="1" r:id="rId1"/>'
          '<sheet name="Months" sheetId="2" r:id="rId2"/>'
          '<sheet name="Categories" sheetId="3" r:id="rId3"/>'
          '<sheet name="Transactions" sheetId="4" r:id="rId4"/>',
        ),
      );
    });

    test('summary carries range, totals and the comparison block', () {
      final s = parts['xl/worksheets/sheet1.xml']!;
      expect(s, contains('<t xml:space="preserve">LocalBudget report</t>'));
      expect(s, contains('<t xml:space="preserve">Mar 2026</t>'));
      expect(s, contains('<t xml:space="preserve">2026-03-07T09:05</t>'));
      expect(s, contains('<t xml:space="preserve">USD</t>'));
      expect(s, contains('<t xml:space="preserve">1234.56</t>')); // Spent
      expect(s, contains('<t xml:space="preserve">1000.00</t>')); // Income
      expect(s, contains('<t xml:space="preserve">-234.56</t>')); // Net
      expect(s, contains('<t xml:space="preserve">Mar 2025</t>'));
      expect(s, contains('<t xml:space="preserve">900.00</t>'));
      expect(s, contains('<t xml:space="preserve">920.00</t>'));
      expect(s, contains('<t xml:space="preserve">+12.3%</t>'));
    });

    test('months sheet pairs each bucket with its compare value', () {
      final s = parts['xl/worksheets/sheet2.xml']!;
      expect(s, contains('<t xml:space="preserve">Month</t>'));
      expect(s, contains('<t xml:space="preserve">Spent (compare)</t>'));
      expect(s, contains('<t xml:space="preserve">2026-02</t>'));
      expect(s, contains('<t xml:space="preserve">934.56</t>'));
      expect(s, contains('<t xml:space="preserve">780.00</t>'));
    });

    test('categories sheet shows spent and share', () {
      final s = parts['xl/worksheets/sheet3.xml']!;
      expect(s, contains('<t xml:space="preserve">Rent</t>'));
      expect(s, contains('<t xml:space="preserve">600.00</t>'));
      expect(s, contains('<t xml:space="preserve">60.0%</t>'));
      expect(s, contains('<t xml:space="preserve">10.0%</t>'));
    });

    test('transactions sheet reuses the CSV columns and sign rules', () {
      final s = parts['xl/worksheets/sheet4.xml']!;
      for (final h in CsvExport.header) {
        expect(s, contains('<t xml:space="preserve">$h</t>'));
      }
      expect(
        s,
        contains(
          '<t xml:space="preserve">Café &amp; &quot;Sons&quot; &lt;x&gt;'
          '</t>',
        ),
      );
      expect(s, contains('<t xml:space="preserve">2026-03-04</t>'));
      expect(s, contains('<t xml:space="preserve">-12.34</t>')); // expense
      expect(s, contains('<t xml:space="preserve">2000.00</t>')); // income
      expect(s, contains('<t xml:space="preserve">-1485</t>')); // JPY, 0 dp
      expect(s, contains('<t xml:space="preserve">Checking</t>'));
    });

    test('an empty report still builds all four sheets', () {
      final empty = unzip(
        ReportWorkbook.encode(
          ReportData(
            rangeLabel: 'Nov 2026',
            generatedAt: DateTime(2026, 11, 3),
            currency: Currency.resolve('USD'),
            spentMinor: 0,
            incomeMinor: 0,
            netMinor: 0,
          ),
        ),
      );
      expect(
        empty['xl/workbook.xml'],
        contains('name="Transactions" sheetId="4"'),
      );
      // Summary keeps its seven label rows; data sheets keep their headers.
      expect(empty['xl/worksheets/sheet1.xml'], contains('LocalBudget report'));
      expect(empty['xl/worksheets/sheet2.xml'], contains('<row r="1">'));
      expect(empty['xl/worksheets/sheet2.xml'], isNot(contains('<row r="2">')));
      expect(empty['xl/worksheets/sheet2.xml'], contains('Month'));
      expect(
        empty['xl/worksheets/sheet2.xml'],
        isNot(contains('Spent (compare)')),
      );
    });

    test('file name mirrors the CSV export', () {
      expect(
        ReportWorkbook.fileName(DateTime(2026, 3, 7)),
        'budget-report-2026-03-07.xlsx',
      );
    });
  });
}
