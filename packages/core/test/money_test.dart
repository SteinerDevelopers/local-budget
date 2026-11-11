// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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

  group('format()', () {
    test('canonical display form', () {
      expect(Money(123456, usd).format(), r'$1,234.56');
      expect(Money(99, usd).format(), r'$0.99');
      expect(Money(-500, usd).format(), r'-$5.00');
      expect(Money(1485, jpy).format(), '¥1,485'); // 0-decimal: no fraction
      expect(Money(-5, jpy).format(), '-¥5');
      expect(Money(12345678, usd).format(), r'$123,456.78');
    });
  });

  // Hardening #21: tryParse is TOTAL — raw OCR text must never crash ingest.
  group('tryParse total contract (#21)', () {
    test('oversized digit runs are null, not FormatException', () {
      expect(Money.tryParse('9' * 30, usd), isNull); // barcode-like run
      expect(Money.tryParse('9780262033843999999999999', usd), isNull);
      expect(Money.tryParse('99,999,999,999,999,999,999.99', usd), isNull);
      expect(Money.tryParse('9' * 40, jpy), isNull);
    });

    test(
      'boundary: last representable major length parses, one more does not',
      () {
        // USD cap is 16 integer digits (18 minor digits total).
        expect(Money.tryParse('9999999999999999.99', usd)?.minorUnits,
            999999999999999999);
        expect(Money.tryParse('99999999999999999.99', usd), isNull);
      },
    );

    test('zero-padded amounts still parse (leading zeros are not overflow)',
        () {
      expect(
          Money.tryParse('00000000000000000000005.00', usd)?.minorUnits, 500);
    });

    test('adversarial corpus never throws', () {
      final garbage = [
        '',
        ' ',
        ',',
        '.',
        ',,,',
        '...',
        r'$$$$$',
        '(',
        '-(',
        '()',
        '1e999',
        '1.2.3.4',
        '0.0.0',
        'ABC€**',
        '123 456 789 012 345 678 901 234 567',
        '1,234,567,890,123,456,789,012',
        '.5.',
        '-.-',
        '9' * 300,
        '−',
        'USD ',
        '\u00A0\u00A0',
        '1\u00A0234\u00A0567\u00A0890\u00A0123\u00A0456\u00A0789',
      ];
      for (final g in garbage) {
        expect(() => Money.tryParse(g, usd), returnsNormally, reason: g);
        expect(() => Money.tryParse(g, jpy), returnsNormally, reason: g);
      }
    });
  });
}
