// #44 — the tail-duplication corrector: only `stored + stored's last
// character` is a misread; everything else must stay its own merchant.
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
        reason: 'a space is not a duplicated glyph',
      );
      expect(correctTailDuplication('Shells', ['Shell Market']), isNull);
      expect(correctTailDuplication('Chevys', ['Chevy']), isNull,
          reason: "'y' doubled is 'yy', not 'ys'");
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
