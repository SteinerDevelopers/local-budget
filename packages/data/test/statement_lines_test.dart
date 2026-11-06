import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';
import 'package:test/test.dart';

/// E11 statement-route groundwork (e11-document-import.md §3): the
/// right-to-left scan over photographed/PDF statement text. Pinned against
/// a frozen clock; every inferred reading must come back amber.
void main() {
  final usd = Currency.known['USD']!;
  final now = DateTime.utc(2026, 11, 4);

  StatementParse? parse(List<String> lines) =>
      StatementLines.tryParse(lines, currency: usd, now: now);

  group('US-format rows', () {
    test('plain lines become rows; signs and keywords decide direction', () {
      final p = parse([
        '10/01/2026 COFFEE SHOP 12.50',
        '10/02/2026 PAYROLL DEPOSIT +1,200.00',
        '10/03/2026 CARD PURCHASE 45.10-',
      ]);
      expect(p, isNotNull);
      expect(p!.rows.length, 3);
      expect(p.skippedLines, 0);

      final r = p.rows[0];
      expect(r.date, DateTime.utc(2026, 10, 1));
      expect(r.minor, 1250);
      expect(r.isIncome, isFalse); // unsigned default is expense
      expect(r.description, 'COFFEE SHOP');
      expect(r.ambiguous, isFalse);

      expect(p.rows[1].isIncome, isTrue); // explicit `+`
      expect(p.rows[1].minor, 120000);
      expect(p.rows[2].minor, 4510); // trailing-minus bank notation
    });

    test('a running-balance column splits amount from balance', () {
      final p = parse([
        '10/01/2026 MARKET 25.00 1,025.00',
        '10/02/2026 FUEL 40.00 985.00',
      ]);
      expect(p!.rows.map((r) => r.minor), [2500, 4000]);
      expect(p.rows.every((r) => r.ambiguous), isTrue); // inferred column
    });

    test('OCR printing one column twice still yields one amount', () {
      final p = parse([
        '10/01/2026 MARKET 25.00 1,025.00',
        '10/02/2026 BANK FEE 10.00 10.00',
      ]);
      final fee = p!.rows[1];
      expect(fee.minor, 1000);
      expect(fee.ambiguous, isTrue);
    });

    test('letters-only line under a row wraps its description', () {
      final p = parse(['10/01/2026 GROCERY STORE 55.25', 'DOWNTOWN PLAZA']);
      expect(p!.rows.length, 1);
      expect(p.rows.single.description, 'GROCERY STORE DOWNTOWN PLAZA');
      expect(p.skippedLines, 0);
    });

    test('reference left of the amount keeps the right-most money', () {
      // Majority single-numeral rows: no balance column, so the two
      // numerals on this line are reference noise + amount, not a split.
      final p = parse([
        '10/01/2026 COFFEE 12.50',
        '10/02/2026 PARKING 8.00',
        '10/03/2026 BOOKSTORE 25.00',
        '10/06/2026 REF 998877 ONLINE PURCHASE 39.99',
      ]);
      expect(p!.rows.last.minor, 3999);
      expect(p.rows.last.ambiguous, isTrue); // extra numeral: amber
    });

    test('a bare four-digit year is noise, not an amount', () {
      final p = parse(['10/07/2026 SUBSCRIPTION 2026 15.00']);
      expect(p!.rows.single.minor, 1500);
      expect(p.rows.single.ambiguous, isFalse); // year skipped, one amount
    });
  });

  group('amber discipline', () {
    test('year-less dates carry the year and go amber', () {
      final p = parse([
        '12/28/2025 SALARY DEPOSIT 2,000.00',
        '01/02 RENT PAYMENT MADE 900.00',
      ]);
      expect(p!.rows.length, 2);
      expect(p.rows[0].ambiguous, isFalse); // on paper: full year
      expect(p.rows[1].date, DateTime.utc(2026, 1, 2)); // Dec→Jan rolls on
      expect(p.rows[1].ambiguous, isTrue); // carried year is an inference
    });

    test('a lone bare whole number reads as money but goes amber', () {
      final p = parse(['10/05/2026 ATM WITHDRAW 100']);
      expect(p!.rows.single.minor, 10000);
      expect(p.rows.single.ambiguous, isTrue); // could be a reference
    });

    test('the same number with cents is plain money', () {
      final p = parse(['10/05/2026 ATM WITHDRAW 100.00']);
      expect(p!.rows.single.minor, 10000);
      expect(p.rows.single.ambiguous, isFalse);
    });
  });

  group('decimal style', () {
    test('provable style contradiction refuses the document', () {
      expect(
        parse(['10/01/2026 CAFE 12.34', '10/02/2026 BAKERY 1.234,56']),
        isNull,
      );
    });

    test('dotted European dates do not fake a style contradiction', () {
      final p = parse(['05.12.2026 GESELLSCHAFT 1.234,56']);
      expect(p, isNotNull);
      expect(p!.rows.single.minor, 123456);
      expect(p.rows.single.date, DateTime.utc(2026, 5, 12));
    });
  });

  group('saved layout profiles (e12 §3)', () {
    final eu = const StatementLayout(decimalComma: true, dayFirst: true);

    test('a known issuer’s saved style settles what alone was refused', () {
      final lines = ['01.10.2026 CAFE 12.34', '02.10.2026 BAKERY 1.234,56'];
      expect(StatementLines.tryParse(lines, currency: usd, now: now), isNull);
      final p = StatementLines.tryParse(
        lines,
        currency: usd,
        now: now,
        layout: eu,
      );
      expect(p, isNotNull);
      // The comma-decimal profile reads 1.234,56 as money and 12.34… stays
      // 12.34 under the later-mark rule; both rows come through.
      expect(p!.rows.length, 2);
      expect(p.rows[1].minor, 123456);
    });

    test('the dayFirst profile overrides document derivation', () {
      // A day-ambiguous pair resolves MM/DD by default; the saved
      // dayFirst layout reads it DD/MM instead.
      const ambiguous = ['05/12/2026 STORE 9.99'];
      final fresh = parse(ambiguous)!;
      expect(fresh.rows.single.date, DateTime.utc(2026, 5, 12));
      final p = StatementLines.tryParse(
        ambiguous,
        currency: usd,
        now: now,
        layout: eu,
      )!;
      expect(p.rows.single.date, DateTime.utc(2026, 12, 5));
    });

    test('parse reports the layout it ran on', () {
      final fresh = parse(['10/01/2026 CAFE 12.34'])!;
      expect(fresh.layout, const StatementLayout(
        decimalComma: false,
        dayFirst: false,
      ));
      final saved = StatementLines.tryParse(
        ['05.12.2026 GESELLSCHAFT 1.234,56'],
        currency: usd,
        now: now,
        layout: eu,
      )!;
      expect(saved.layout, eu);
    });

    test('encode/decode round-trips; junk decodes to null', () {
      final round = StatementLayout.decode(eu.encode());
      expect(round, eu);
      expect(StatementLayout.decode('not json'), isNull);
      expect(StatementLayout.decode('{"dc":1}'), isNull);
      expect(StatementLayout.decode(null), isNull);
    });
  });

  group('item blocks (e12 §5)', () {
    const itemized = [
      '12/05/2026 CITY HOSPITAL 250.00 4,300.00',
      'X-RAY READING 120.00',
      'LAB WORK 80.00',
      'SUPPLY FEE 50.00',
      'TOTAL CHARGES 250.00',
      '12/07/2026 DELTA FOODS 30.00 4,270.00',
    ];

    test('a block reconciling to the row amount is kept, in order', () {
      final p = parse(itemized)!;
      expect(p.rows, hasLength(2));
      final hosp = p.rows.first;
      expect(hosp.description, contains('CITY HOSPITAL'));
      expect(hosp.items, hasLength(3));
      expect(hosp.items!.map((e) => e.name), [
        'X-RAY READING',
        'LAB WORK',
        'SUPPLY FEE',
      ]);
      expect(hosp.items!.fold<int>(0, (s, e) => s + e.totalMinor), hosp.minor);
      // The next row has no block of its own.
      expect(p.rows.last.items, isNull);
    });

    test('a block that does not reconcile is dropped, the row kept', () {
      final p = parse([
        '12/05/2026 CITY HOSPITAL 250.00 4,300.00',
        'X-RAY READING 130.00', // 130 + 80 + 50 ≠ 250
        'LAB WORK 80.00',
        'SUPPLY FEE 50.00',
      ])!;
      expect(p.rows.single.items, isNull);
      expect(p.rows.single.minor, 25000);
    });

    test('summary vocabulary closes the block before it overruns', () {
      // The second block under TOTAL would swallow the summary price if
      // the block did not stop at the summary word.
      final p = parse([
        '12/05/2026 CITY HOSPITAL 250.00 4,300.00',
        'X-RAY READING 120.00',
        'LAB WORK 80.00',
        'SUPPLY FEE 50.00',
        'TOTAL CHARGES 250.00',
        'ORPHAN FEE 9.00',
        'OTHER FEE 9.00',
      ])!;
      expect(p.rows.single.items, hasLength(3));
    });

    test('a lone price line is not an item (single-item blocks stay silent)',
        () {
      final p = parse([
        '12/05/2026 CITY HOSPITAL 250.00 4,300.00',
        'X-RAY READING 250.00',
      ])!;
      expect(p.rows.single.items, isNull);
    });
  });

  group('refusals', () {
    test('dates far outside the believable window are skipped', () {
      final p = parse(['01/01/2019 OLDSCHOOL 5.00']);
      expect(p!.rows, isEmpty);
      expect(p.skippedLines, 1);
    });

    test('letter-only noise without a preceding row is skipped', () {
      final p = parse(['CHECKING ACCOUNT ACTIVITY']);
      expect(p!.rows, isEmpty);
      expect(p.skippedLines, 1);
    });

    test('blank input parses to nothing', () {
      expect(parse(['', '   ']), isNull);
    });
  });
}
