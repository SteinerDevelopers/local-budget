import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('CategoryHints (e12 §2)', () {
    test('a well-known brand reads high', () {
      expect(CategoryHints.suggest('UBER TRIP HELP.PEOPLE.COM'),
          ('Transport', FieldConfidence.high));
      expect(
          CategoryHints.suggest('netflix.com'), ('Fun', FieldConfidence.high));
      expect(CategoryHints.suggest('COSTCO WHOLESALE #123'), isNull);
      expect(CategoryHints.suggest('STARBUCKS STORE 4018'),
          ('Food', FieldConfidence.high));
      expect(CategoryHints.suggest('PG&E SERVICES'),
          ('Utilities', FieldConfidence.high));
      expect(CategoryHints.suggest('CVS/PHARMACY #03412'),
          ('Health', FieldConfidence.high));
    });

    test('generic vocabulary reads medium, never high', () {
      expect(CategoryHints.suggest('GREEN GROCERS'),
          ('Food', FieldConfidence.medium));
      expect(CategoryHints.suggest('CORNER PARKING'),
          ('Transport', FieldConfidence.medium));
      expect(CategoryHints.suggest('RIVERSIDE DENTAL GROUP'),
          ('Health', FieldConfidence.high));
      expect(CategoryHints.suggest('CITY WATER SEWER'),
          ('Utilities', FieldConfidence.medium));
    });

    test('high wins over an earlier medium', () {
      // "market" (medium Food) appears before the NETFLIX brand token —
      // the high match must still decide.
      expect(CategoryHints.suggest('FARMERS MARKET — NETFLIX BILLPAY'),
          ('Fun', FieldConfidence.high));
    });

    test('unknown text stays silent', () {
      expect(CategoryHints.suggest('ACME HOLDINGS LLC'), isNull);
      expect(CategoryHints.suggest(''), isNull);
      expect(CategoryHints.suggest('   '), isNull);
    });

    test('only the six suggestable seed names ever come back', () {
      for (final text in [
        'UBER TRIP',
        'CITY WATER',
        'SPOTIFY',
        'RALPHS GROCERY',
        'WALGREEN #77',
      ]) {
        final hit = CategoryHints.suggest(text);
        expect(CategoryHints.suggested, contains(hit!.$1), reason: text);
      }
    });
  });
}
