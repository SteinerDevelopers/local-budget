import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/quickadd/amount_pad.dart';

void main() {
  final usd = Currency.resolve('USD');
  final jpy = Currency.resolve('JPY');

  AmountPad type(String keys, {Currency? currency}) {
    final pad = AmountPad(currency: currency ?? usd);
    for (final k in keys.split('')) {
      k == '.' ? pad.dot() : pad.digit(k);
    }
    return pad;
  }

  group('AmountPad (§2.2 keypad input)', () {
    test('empty shows dimmed 0 placeholder, zero money', () {
      final pad = AmountPad(currency: usd);
      expect(pad.display, '0');
      expect(pad.isPlaceholder, isTrue);
      expect(pad.money, Money.zero(usd));
    });

    test('typed digits are exact minor units, no float', () {
      expect(type('12.40').money, Money(1240, usd));
    });

    test('fraction is capped at the currency minor units', () {
      final pad = type('12.459'); // third decimal ignored
      expect(pad.display, '12.45');
      expect(pad.money, Money(1245, usd));
    });

    test('dot first becomes 0.; double dot ignored', () {
      final pad = AmountPad(currency: usd)
        ..dot()
        ..dot();
      expect(pad.display, '0.');
      pad.digit('5');
      expect(pad.money, Money(50, usd)); // $0.50
    });

    test('lone zero absorbs the dot', () {
      final pad = type('0.');
      expect(pad.display, '0.');
    });

    test('backspace peels one char at a time', () {
      final pad = type('12');
      pad.back();
      expect(pad.display, '1');
      pad.back();
      expect(pad.isEmpty, isTrue);
      pad.back(); // no-op on empty
      expect(pad.display, '0');
    });

    test('zero-decimal currency ignores the dot entirely', () {
      final pad = type('12.', currency: jpy);
      expect(pad.display, '12');
      expect(pad.money, Money(12, jpy));
    });

    test('integer part is capped', () {
      final pad = type('1234567890123');
      expect(pad.display, '123456789');
    });

    test('12.4 in USD is 1240 minor units (pad, not float round)', () {
      expect(type('12.4').money, Money(1240, usd));
    });
  });
}
