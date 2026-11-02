import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency.resolve('USD');
  final jpy = Currency.resolve('JPY');

  group('Money arithmetic (integer minor units)', () {
    test('0.1 + 0.2 is exactly 0.30 — the classic float trap', () {
      final a = Money.tryParse('0.10', usd)!;
      final b = Money.tryParse('0.20', usd)!;
      expect((a + b).minorUnits, 30);
    });

    test('mixed-currency arithmetic throws', () {
      expect(() => Money(100, usd) + Money(100, jpy), throwsArgumentError);
    });

    test('sum guards mixed currencies', () {
      expect(() => Money.sum([Money(1, usd), Money(1, jpy)], usd),
          throwsArgumentError);
    });

    test('split re-sums exactly (largest-remainder apportionment)', () {
      final m = Money(100, usd); // $1.00 into 3-way split
      expect(m.split([1, 1, 1]).map((p) => p.minorUnits), [34, 33, 33]);
      expect(m.split([5, 1]).map((p) => p.minorUnits), [83, 17]);
      // pathological: 1 cent three ways — still exact, never invents a cent
      expect(
          Money(1, usd)
              .split([1, 1, 1]).fold<int>(0, (a, p) => a + p.minorUnits),
          1);
    });
  });

  group('Money.parse', () {
    test('plain and symbol-prefixed', () {
      expect(Money.tryParse('12.34', usd)!.minorUnits, 1234);
      expect(Money.tryParse(r'$12.34', usd)!.minorUnits, 1234);
      expect(Money.tryParse('USD 12.34', usd)!.minorUnits, 1234);
      expect(Money.tryParse('  € 9.99 ', Currency.resolve('EUR'))!.minorUnits,
          999);
    });

    test('thousands separators', () {
      expect(Money.tryParse('1,234.56', usd)!.minorUnits, 123456);
      expect(Money.tryParse('1.234,56', usd, decimalComma: true)!.minorUnits,
          123456);
      expect(Money.tryParse('1\u00A0234.56', usd)!.minorUnits, 123456);
      // auto-detect: last separator is the decimal one
      expect(Money.tryParse('1.234,56', usd)!.minorUnits, 123456);
      expect(Money.tryParse('1,234.56', usd)!.minorUnits, 123456);
    });

    test('zero-decimal currency (JPY): no fractional creep', () {
      expect(Money.tryParse('¥1,500', jpy)!.minorUnits, 1500);
      expect(Money.tryParse('1500', jpy)!.major, 1500);
    });

    test('three-minor currency (BHD)', () {
      final bhd = Currency.resolve('BHD');
      expect(Money.tryParse('12.345', bhd)!.minorUnits, 12345);
    });

    test('negatives and accounting parens', () {
      expect(Money.tryParse('-4.20', usd)!.minorUnits, -420);
      expect(Money.tryParse('(4.20)', usd)!.minorUnits, -420);
      expect(
          Money.tryParse('4,20−', Currency.resolve('EUR'), decimalComma: true)!
              .minorUnits,
          -420);
    });

    test('rounds excess fraction digits half-up', () {
      expect(Money.tryParse('1.999', usd)!.minorUnits, 200);
      expect(Money.tryParse('1.994', usd)!.minorUnits, 199);
    });

    test('rejects junk', () {
      expect(Money.tryParse('', usd), isNull);
      expect(Money.tryParse('abc', usd), isNull);
      expect(Money.tryParse('1.2.3', usd), isNull);
      expect(Money.tryParse('12,', usd), isNull);
    });
  });

  group('FX conversion (explicit rounding only)', () {
    test('USD->EUR at 0.925, half-away-from-zero at target minor step', () {
      final usdMoney = Money.tryParse('10.00', usd)!; // 1000 cents
      final eur = usdMoney.convertTo(Currency.resolve('EUR'), 0.925);
      expect(eur.minorUnits, 925);
    });

    test('cross-minor-scale conversion USD->JPY', () {
      // $10 at 148.5 = ¥1,485 -> 1485 minor units (JPY minor step = 1 yen)
      final jpyMoney = Money.tryParse('10.00', usd)!.convertTo(jpy, 148.5);
      expect(jpyMoney.minorUnits, 1485);
    });

    test('invalid rates throw', () {
      expect(() => Money(100, usd).convertTo(jpy, 0), throwsArgumentError);
      expect(() => Money(100, usd).convertTo(jpy, double.nan),
          throwsArgumentError);
    });
  });
}
