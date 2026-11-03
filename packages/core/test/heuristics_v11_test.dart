/// E2 v1.1 tests (device feedback 2026-11-03): OCR line reassembly,
/// cross-anchor line joins, and bill vocabularies — e2-capture.md §3 v1.1.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  // USD base, fixed clock — same harness as heuristics_test.dart.
  final heur = () => ReceiptHeuristics(
      currency: Currency.find('USD')!, now: DateTime.utc(2026, 11, 3));

  group('OcrLineAssembly', () {
    OcrWord w(String t, double x, double y, {double h = 20}) =>
        OcrWord(text: t, centerX: x, centerY: y, height: h);

    test('splits label/amount columns back into visual lines', () {
      final lines = OcrLineAssembly.assemble([
        w('TOTAL', 30, 102),
        w('\$42.50', 220, 100), // same visual line, right column
        w('TAX', 30, 80),
        w('3.10', 210, 79),
      ]);
      expect(lines, ['TAX 3.10', 'TOTAL \$42.50']);
    });

    test('tolerance follows median word height, not a magic constant', () {
      // Tall 60px glyphs: centers 25px apart are still one line.
      final lines = OcrLineAssembly.assemble([
        w('TOTAL', 30, 100, h: 60),
        w('\$5.00', 200, 125, h: 60),
      ]);
      expect(lines, ['TOTAL \$5.00']);
      // Same 25px gap with small glyphs: two lines.
      expect(
        OcrLineAssembly
            .assemble([w('TOTAL', 30, 100, h: 14), w('\$5.00', 200, 125, h: 14)]),
        ['TOTAL', '\$5.00'],
      );
    });

    test('a tilted receipt stays on one drifting line', () {
      final lines = OcrLineAssembly.assemble([
        w('ITEM', 20, 100),
        w('2.00', 200, 106),
        w('x2', 320, 112),
        w('TOTAL', 20, 150), // clear break
        w('6.00', 200, 157),
      ]);
      expect(lines, ['ITEM 2.00 x2', 'TOTAL 6.00']);
    });

    test('input order never matters; blanks are dropped', () {
      final lines = OcrLineAssembly.assemble([
        w('  ', 90, 100),
        w('BREAD', 150, 50),
        w('SHOP', 20, 20),
        w('2.49', 210, 51),
      ]);
      expect(lines, ['SHOP', 'BREAD 2.49']);
    });
  });

  group('total v1.1 — OCR-split and reordered lines', () {
    test('anchor alone, amount two lines down (column split)', () {
      final t = heur().guessTotal([
        'CORNER MARKET',
        'MILK 2.00',
        'TOTAL',
        '2 ITEMS', // integer without money look: rejected
        '\$42.50',
      ])!;
      expect(t.amount.minorUnits, 4250);
      expect(t.confidence, FieldConfidence.low); // re-joined: demoted
    });

    test('barcode below a bare TOTAL is never the total', () {
      expect(
        heur().guessTotal(['SHOP', 'TOTAL', '123456789012']),
        isNull,
      );
    });

    test('amount left of the anchor', () {
      final t = heur().guessTotal(['POS-9', '42.50 TOTAL'])!;
      expect(t.amount.minorUnits, 4250);
      expect(t.confidence, FieldConfidence.medium); // same line: no demotion
    });

    test('decimals beat bare integers on the anchor line', () {
      final t = heur().guessTotal(['STORE', 'TOTAL 4 ITEMS 42.50'])!;
      expect(t.amount.minorUnits, 4250);
    });

    test('integer totals still work (JPY-style)', () {
      final t = heur().guessTotal(['RAMEN', 'TOTAL ¥1,200'])!;
      expect(t.amount.minorUnits, 1200);
    });
  });

  group('document classification', () {
    test('retail receipt stays receipt', () {
      expect(
        heur().classify([
          'MAIN STREET CAFE',
          'CLUB SANDWICH 8.50',
          'TOTAL 9.34',
        ]),
        DocType.receipt,
      );
    });

    test('one lone bill-ish line is not enough — needs two signatures', () {
      expect(
        heur().classify(['MAGA PETROLEUM', 'DUE DATE 11/25', 'TOTAL 55.20']),
        DocType.receipt, // only DUE DATE: a fuel receipt with a promo
      );
    });

    test('card statement and utility bill classify from signatures', () {
      expect(
        heur().classify([
          'HARBOR BANK CREDIT CARD',
          'ACCOUNT SUMMARY',
          'MINIMUM PAYMENT DUE 35.00',
          'CREDIT LIMIT 5,000.00',
        ]),
        DocType.cardStatement,
      );
      expect(
        heur().classify([
          'CITY WATER & SEWER',
          'SERVICE PERIOD 10/01-10/31',
          'USAGE 4,800 GALLONS',
        ]),
        DocType.utilityBill,
      );
    });
  });

  group('bill vocabularies', () {
    test('card statement: statement balance wins, minimum never does', () {
      const lines = [
        'HARBOR BANK — CREDIT CARD SERVICES',
        'ACCOUNT NUMBER 4321-XXXX-XXXX-9876',
        'ACCOUNT SUMMARY',
        'PREVIOUS BALANCE 312.40',
        'PAYMENT CREDIT -200.00',
        'NEW CHARGES 1,122.16',
        'NEW BALANCE 1,234.56',
        'MINIMUM PAYMENT DUE 35.00',
        'CREDIT LIMIT 5,000.00',
        'PAYMENT DUE DATE 11/25/26',
      ];
      expect(heur().classify(lines), DocType.cardStatement);
      final t = heur().guessTotal(lines)!;
      expect(t.amount.minorUnits, 123456);
      expect(t.confidence, FieldConfidence.high);
    });

    test('minimum-only statement yields nothing rather than the trap', () {
      const lines = [
        'HARBOR BANK CREDIT CARD',
        'ACCOUNT SUMMARY FOR OCTOBER',
        'MINIMUM PAYMENT DUE 35.00',
      ];
      expect(heur().classify(lines), DocType.cardStatement);
      expect(heur().guessTotal(lines), isNull);
    });

    test('utility bill: TOTAL AMOUNT DUE, past-due never', () {
      const lines = [
        'PACIFIC GAS & ELECTRIC',
        'ACCOUNT NUMBER 8821-4417',
        'SERVICE PERIOD 10/01/26 - 10/31/26',
        'PRESENT BALANCE 138.20',
        'PAST DUE AMOUNT 22.90',
        'METER READINGS 44812 45260',
        'USAGE 448 KWH',
        'TOTAL AMOUNT DUE 142.75',
        'DUE BY 11/25/26',
      ];
      expect(heur().classify(lines), DocType.utilityBill);
      final t = heur().guessTotal(lines)!;
      expect(t.amount.minorUnits, 14275);
      expect(t.confidence, FieldConfidence.high);
    });

    test('utility with only AMOUNT DUE still resolves', () {
      const lines = [
        'CITY WATER',
        'BILLING PERIOD OCTOBER',
        'GALLONS USED 3,100',
        'AMOUNT DUE 55.20',
      ];
      expect(heur().classify(lines), DocType.utilityBill);
      expect(heur().guessTotal(lines)!.amount.minorUnits, 5520);
    });

    test('full draft: card statement end-to-end', () {
      final d = heur().extract([
        'HARBOR BANK CREDIT CARD',
        'ACCOUNT SUMMARY',
        'NEW BALANCE 1,234.56',
        'STATEMENT PERIOD 10/01/2026 - 10/31/2026',
        'MINIMUM PAYMENT DUE 35.00',
        'DUE DATE 11/25/2026',
      ]);
      expect(d.total!.minorUnits, 123456);
      expect(d.totalConfidence, FieldConfidence.high);
      expect(d.merchant, 'HARBOR BANK CREDIT CARD');
    });
  });
}
