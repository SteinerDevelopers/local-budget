import 'package:core/core.dart';
import 'package:test/test.dart';

final usd = Currency.resolve('USD');

ReceiptHeuristics h(List<String>? _, DateTime now) =>
    ReceiptHeuristics(currency: usd, now: now);

void main() {
  final now = DateTime(2026, 11, 2);
  ReceiptHeuristics heur() => ReceiptHeuristics(currency: usd, now: now);

  group('total extraction', () {
    test('classic retail receipt: bottom TOTAL wins over subtotal/tax', () {
      final lines = [
        'CORNER CAFE',
        '123 MAIN ST',
        '03/15/2026  14:22',
        'LATTE 4.50',
        'CROISSANT 3.25',
        'SUBTOTAL 7.75',
        'TAX 0.68',
        'TOTAL 8.43',
        'CASH 10.00',
        'CHANGE 1.57',
      ];
      final t = heur().guessTotal(lines)!;
      expect(t.amount.minorUnits, 843);
    });

    test('utility bill: TOTAL DUE beats charge-section TOTAL', () {
      final lines = [
        'CITY POWER & LIGHT',
        'SERVICE CHARGES      TOTAL 112.40',
        'TAXES & FEES           9.85',
        'PREVIOUS BALANCE      0.00',
        'TOTAL DUE            122.25',
        'PAY BY 11/25/26',
      ];
      final t = heur().guessTotal(lines)!;
      expect(t.amount.minorUnits, 12225);
      expect(t.confidence, FieldConfidence.high);
    });

    test('SUBTOTAL is never the total (no TOTAL line present)', () {
      final lines = ['STORE X', 'ITEM A 5.00', 'SUBTOTAL 5.00', 'CARD 5.00'];
      expect(heur().guessTotal(lines), isNull);
    });

    test('TOTAL TAX / TOTAL SAVINGS excluded; total is 5 lines up', () {
      final lines = [
        'MARKET',
        'GROCERIES',
        'TOTAL 42.10',
        'TOTAL TAX 3.15',
        'TOTAL SAVINGS 4.00',
        'TOTAL ITEMS 12',
      ];
      final t = heur().guessTotal(lines)!;
      expect(t.amount.minorUnits, 4210);
    });

    test('currency-symbol amounts', () {
      final lines = ['CAFE', 'TOTAL \$12.99'];
      expect(heur().guessTotal(lines)!.amount.minorUnits, 1299);
    });
  });

  group('date extraction', () {
    test('ISO wins, unambiguous high', () {
      final d = heur().guessDate(['INV', 'Date: 2026-03-15', 'TOTAL 1.00'])!;
      expect(d.date, DateTime(2026, 3, 15));
      expect(d.ambiguous, false);
      expect(d.confidence, FieldConfidence.high);
    });

    test('month-name formats', () {
      expect(heur().guessDate(['Mar 5, 2026', 'TOTAL 2.00'])!.date,
          DateTime(2026, 3, 5));
      expect(heur().guessDate(['5 March 2026'])!.date, DateTime(2026, 3, 5));
    });

    test('unambiguous d/m via day>12', () {
      final d = heur().guessDate(['25.03.2026', 'TOTAL 1.00'])!;
      expect(d.date, DateTime(2026, 3, 25));
      expect(d.ambiguous, false);
    });

    test('03/04/26 is flagged ambiguous, never silently guessed', () {
      final d = heur().guessDate(['03/04/26', 'TOTAL 1.00'])!;
      expect(d.ambiguous, true);
      expect(d.confidence, FieldConfidence.low);
    });

    test('future dates rejected', () {
      expect(heur().guessDate(['2026-12-25', 'TOTAL 1.00']), isNull);
    });
  });

  group('merchant guess', () {
    test('first plausible line', () {
      expect(
          heur().guessMerchant(
              ['GREEN GROCERS', '123 OAK STREET', 'TEL 555-1212']),
          'GREEN GROCERS');
    });

    test('skips noise (receipt headers, thank-yous)', () {
      expect(
          heur().guessMerchant([
            'RECEIPT',
            'THANK YOU FOR VISITING!',
            'BOSTON MARKET',
            'BOSTON, MA',
          ]),
          'BOSTON MARKET');
    });

    test('all-noise returns null (review sheet will ask)', () {
      expect(heur().guessMerchant(['123 456', '***', '05/05/2026']), isNull);
    });
  });

  group('full draft', () {
    test('real grocery receipt end-to-end', () {
      final draft = heur().extract([
        'FRESH MART #204',
        '4400 LAKEVIEW AVE',
        'STORE 0204 REG 07 TRX 4411',
        '03/15/2026 14:22:01',
        'BANANAS 1.29',
        'MILK 2x 3.00 6.00',
        'BREAD 2.49',
        'SUBTOTAL 9.78',
        'TAX 0.55',
        'TOTAL 10.33',
        'VISA ****1234 APPROVED',
        'THANK YOU!',
      ]);
      expect(draft.merchant, 'FRESH MART #204');
      expect(draft.date, DateTime(2026, 3, 15));
      expect(draft.total!.minorUnits, 1033);
      expect(draft.isComplete, true);
      expect(draft.rawLines.length, 12);
    });
  });
}
