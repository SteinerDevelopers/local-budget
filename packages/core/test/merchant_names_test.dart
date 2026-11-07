// #44 — the tail-appendage corrector: only stored name + ONE trailing
// character is a misread; anything longer or shorter stays its own
// merchant.
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('correctTailDuplication (#44)', () {
    test('the Walmart bounce: Walmartk resolves to the stored spelling', () {
      expect(correctTailDuplication('Walmartk', ['Walmart']), 'Walmart');
      expect(correctTailDuplication('WalmartK', ['walmart']), 'walmart');
    });

    test('different merchants are never merged', () {
      expect(
        correctTailDuplication('Costco Plus', ['Costco']),
        isNull,
        reason: 'one extra character means one character, not a word',
      );
      expect(correctTailDuplication('Shells', ['Shell Market']), isNull);
      expect(correctTailDuplication('Walmar', ['Walmart']), isNull,
          reason: 'truncation is not an appendage');
    });

    test('documented trade: Target in the ledger resolves a scanned Targets',
        () {
      // Deliberate (see doc comment): the review sheet keeps the field
      // editable; a silent near-duplicate merchant row would not.
      expect(correctTailDuplication('Targets', ['Target']), 'Target');
    });

    test('exact names and unknown names pass through as null', () {
      expect(correctTailDuplication('Walmart', ['Walmart']), isNull);
      expect(correctTailDuplication('Targett', ['Walmart']), isNull);
      expect(correctTailDuplication('Kroger', const <String>[]), isNull);
    });

    test('tiny names are untouchable', () {
      expect(correctTailDuplication('BB', ['B']), isNull);
      expect(correctTailDuplication('Tll', ['Tl']), isNull);
    });
  });
}
