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
    test('first plausible line is high confidence', () {
      final m = heur()
          .guessMerchant(['GREEN GROCERS', '123 OAK STREET', 'TEL 555-1212'])!;
      expect(m.name, 'GREEN GROCERS');
      expect(m.confidence, FieldConfidence.high);
    });

    test('skips noise (receipt headers, thank-yous) → medium', () {
      final m = heur().guessMerchant([
        'RECEIPT',
        'THANK YOU FOR VISITING!',
        'BOSTON MARKET',
        'BOSTON, MA',
      ])!;
      expect(m.name, 'BOSTON MARKET');
      expect(m.confidence, FieldConfidence.medium);
    });

    test('all-noise returns null (review sheet will ask)', () {
      expect(heur().guessMerchant(['123 456', '***', '05/05/2026']), isNull);
    });

    test('template-statement boilerplate never mints a payee (device trace)', () {
      // Real ML Kit lines off the SL219A, CFPB "Building Blocks" raster
      // (US Government work, public domain), captured 2026-11-05. The page
      // header + labelled field rows used to mint "E BUILDING BLOCKS STUDENT
      // HANDOUT" as the merchant; the issuer is absent, so abstain is right.
      expect(
        heur().guessMerchant([
          'E BUILDING BLOCKS STUDENT HANDOUT',
          'Sample credit card statement',
          'Name: Susan Doe For Lost or Stolen Card, Call:',
          'Address: 1234 Main Street, Anytown, USA 1-800-XXX-XXXX',
          'Account Number: 12345-67-8907',
          'Payment Information',
        ]),
        isNull,
      );
    });
  });

  group('E2 spec alignment (e2-capture.md §3)', () {
    test('anchor-line currency code overrides base', () {
      final t = heur().guessTotal(['HOTEL', 'TOTAL 58.00 EUR'])!;
      expect(t.amount.currency.code, 'EUR');
      expect(t.amount.minorUnits, 5800);
    });

    test('euro/pound/rupee symbols resolve', () {
      expect(
          heur()
              .guessTotal(['Cafe', 'TOTAL \u20AC12.50'])!
              .amount
              .currency
              .code,
          'EUR');
      expect(
          heur().guessTotal(['SHOP', 'TOTAL \u00A34.20'])!.amount.currency.code,
          'GBP');
      expect(
          heur()
              .guessTotal(['KIRANA', 'TOTAL \u20B9950.00'])!
              .amount
              .currency
              .code,
          'INR');
    });

    test('yen without decimals is JPY, with decimals is CNY', () {
      expect(
          heur()
              .guessTotal(['RAMEN', 'TOTAL \u00A51,200'])!
              .amount
              .currency
              .code,
          'JPY');
      expect(
          heur().guessTotal(['RAMEN', 'TOTAL \u00A51,200'])!.amount.minorUnits,
          1200);
      expect(
          heur()
              .guessTotal(['MARKET', 'TOTAL \u00A512.40'])!
              .amount
              .currency
              .code,
          'CNY');
      expect(
          heur().guessTotal(['MARKET', 'TOTAL \u00A512.40'])!.amount.minorUnits,
          1240);
    });

    test('dollar stays base currency — never re-guessed', () {
      final t = heur().guessTotal(['CAFE', 'TOTAL \$12.99'])!;
      expect(t.amount.currency.code, 'USD');
    });

    test('NET TOTAL is high confidence (substring trap vs bare TOTAL)', () {
      final t = heur().guessTotal(['ORDER', 'NET TOTAL 50.00'])!;
      expect(t.confidence, FieldConfidence.high);
      expect(t.amount.minorUnits, 5000);
    });

    test('GRAND TOTAL anchor works', () {
      final t = heur().guessTotal(['BANQUET', 'GRAND TOTAL 1,250.00'])!;
      expect(t.confidence, FieldConfidence.high);
      expect(t.amount.minorUnits, 125000);
    });

    test('bare AMOUNT is a low-confidence last resort', () {
      final t = heur().guessTotal(['DONATION', 'AMOUNT 20.00'])!;
      expect(t.confidence, FieldConfidence.low);
      expect(t.amount.minorUnits, 2000);
    });

    test('AMOUNT TENDERED / AMOUNT PAID are never totals', () {
      expect(heur().guessTotal(['SHOP', 'AMOUNT TENDERED 20.00']), isNull);
      expect(
          heur()
              .guessTotal(['CLUB', 'AMOUNT PAID 100.00', 'BALANCE DUE 40.00'])!
              .amount
              .minorUnits,
          4000);
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
