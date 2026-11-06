// E13 §3/§5 — the payee sanity gate: junk widens to silence, keepers keep,
// and a doubled unpronounceable mark still ships (at medium). Table cases
// are the regression bar the spec promises.
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency.resolve('USD');
  final now = DateTime(2026, 11, 2);
  ReceiptHeuristics heur() => ReceiptHeuristics(currency: usd, now: now);

  group('junk gate (unit)', () {
    test('unpronounceable raster tokens are junk', () {
      expect(PayeeSanity.junkName('BOUI FVAFD'), isTrue);
      expect(PayeeSanity.junkName('AAAAA'), isTrue);
      expect(PayeeSanity.junkName('IIIII'), isTrue);
      expect(PayeeSanity.junkName('FVAFD'), isTrue);
    });

    test('letter brands and odd-but-real names pass', () {
      for (final keeper in [
        'XYZ STORE',
        'CNN CAFE',
        'TGI FRIDAYS',
        'TV DINER',
        'H&R BLOCK',
        'M&M FOODS',
        'WAL-MART #1234',
        'AMZN MKTP', // seeded whitelist
        'RHYTHM RECORDS',
        'TOTAL WINE & SPIRITS', // no digits: not amount prose
      ]) {
        expect(PayeeSanity.junkName(keeper), isFalse, reason: keeper);
      }
    });

    test('amount prose with digits is caught by the total guard', () {
      expect(PayeeSanity.totalishWithDigits('TOTAL: \$45.99'), isTrue);
      expect(PayeeSanity.totalishWithDigits('BALANCE 1,204.00'), isTrue);
      expect(PayeeSanity.totalishWithDigits('TOTAL WINE'), isFalse);
    });
  });

  group('guessMerchant through the gate', () {
    test('lone raster junk yields honest silence', () {
      expect(heur().guessMerchant(['BOUI FVAFD']), isNull);
    });

    test('junk on line 1 hands the turn to the real name below', () {
      final m = heur().guessMerchant([
        'BOUI FVAFD',
        'ENERGEL',
        'ACCOUNT SUMMARY 04/2026',
        'TOTAL DUE 61.20',
      ]);
      expect(m!.name, 'ENERGEL');
      expect(m.confidence, FieldConfidence.medium);
    });

    test('a doubled unpronounceable mark ships at medium, never high', () {
      final m = heur().guessMerchant([
        'XQZP STORE',
        '04/12/2026  22.40',
        'XQZP STORE',
        'TOTAL 22.40',
      ]);
      expect(m!.name, 'XQZP STORE');
      expect(m.confidence, FieldConfidence.medium);
    });

    test('TOTAL-with-digits lines never mint a merchant', () {
      expect(
        heur().guessMerchant(
            ['TOTAL: \$45.99', 'CORNER CAFE', 'TOTAL 45.99'])!.name,
        'CORNER CAFE',
      );
    });

    test('echo runs (AAAAA) are junk, not a brand', () {
      expect(
        heur().guessMerchant(['AAAAA', 'BRIGHT MART', 'TOTAL 9.99'])!.name,
        'BRIGHT MART',
      );
    });

    test('existing keepers and bounces are untouched', () {
      expect(
        heur().guessMerchant(['GREEN GROCERS', '123 OAK STREET'])!.name,
        'GREEN GROCERS',
      );
      expect(
        heur().guessMerchant([
          'https://pay.example.com',
          'PARKWAY ENERGY',
          'AMOUNT DUE 61.20',
        ])!.name,
        'PARKWAY ENERGY',
      );
    });
  });

  group('BillDraft payee through the gate', () {
    test('junk-first raster photo ships no payee, but keeps the amount', () {
      final d = BillDraft.draft(
        ['BOUI FVAFD', '04/12/2026', 'TOTAL DUE 22.40'],
        currency: usd,
        now: now,
      );
      expect(d.payee, isNull);
      expect(d.amountDue?.minorUnits, 2240);
    });
  });

  group('digit-leading merchants (E13 §4)', () {
    test('vocabulary keepers survive at medium', () {
      for (final keeper in [
        '99¢ ONLY',
        '24 HOUR MARKET',
        '5 GUYS BURGER',
        '1-800-FLOWERS',
        '24/7 MARKET',
        '6 PM CAFE',
      ]) {
        final m = heur().guessMerchant([keeper, 'TOTAL 9.99']);
        expect(m?.name, keeper, reason: keeper);
        expect(m?.confidence, FieldConfidence.medium, reason: keeper);
      }
    });

    test('a doubled keeper on line 1 earns high', () {
      final m = heur().guessMerchant([
        '99¢ ONLY',
        '04/12/2026',
        '99¢ ONLY',
        'TOTAL 7.75',
      ]);
      expect(m!.name, '99¢ ONLY');
      expect(m.confidence, FieldConfidence.high);
    });

    test('dates, phones and discount prose stay dead', () {
      for (final noise in [
        '03/15 DUE',
        '10 OFF TOTAL',
        '10% DISCOUNT',
        '1234 5678 9012',
        '03/20/24',
        '555-1212 CALL',
      ]) {
        expect(
          heur().guessMerchant([noise, '22.40']),
          isNull,
          reason: noise,
        );
      }
    });

    test('no vocabulary and one occurrence is not enough', () {
      expect(heur().guessMerchant(['1 HOUR PHOTO', 'TOTAL 9.00']), isNull);
    });

    test('the name never leaks into the amount', () {
      final lines = ['99¢ ONLY', 'MILK 4.00', 'BREAD 3.50', 'TOTAL 12.50'];
      expect(heur().guessMerchant(lines)!.name, '99¢ ONLY');
      expect(heur().guessTotal(lines)!.amount.minorUnits, 1250);
    });
  });
}
