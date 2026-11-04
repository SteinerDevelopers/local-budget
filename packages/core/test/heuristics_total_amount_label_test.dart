// Device feedback 2026-11-04: a Vera Bradley photo capture showed no total;
// the receipt's total line was shaped `Total Amount:        $xxx.xx`.
// These cases pin every OCR layout of that label (clean line, column split,
// colon glued, tender block below, uppercase) so the label can never regress
// out of coverage again.
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 4);
  final usd = Currency.resolve('USD');
  ReceiptHeuristics h() => ReceiptHeuristics(currency: usd, now: now);

  test('retail receipt, "Total Amount:" with wide gap on one line', () {
    final r = h().guessTotal([
      'VERA BRADLEY',
      'STORE #1120',
      '02 Nov 2026  3:44 PM',
      'SCARF LUCY \$24.00',
      'TOTE POPPY \$39.50',
      'SUBTOTAL \$63.50',
      'SALES TAX \$5.33',
      'Total Amount:        \$68.83',
      'VISA 1234 \$68.83',
      'THANK YOU FOR SHOPPING WITH US!',
    ]);
    expect(r?.amount.minorUnits, 6883);
  });

  test('ocr column split: label line then amount line', () {
    final r = h().guessTotal([
      'VERA BRADLEY',
      'SUBTOTAL \$63.50',
      'SALES TAX \$5.33',
      'Total Amount:',
      '\$68.83',
      'THANK YOU!',
    ]);
    expect(r?.amount.minorUnits, 6883);
  });

  test('colon glued to amount', () {
    final r = h().guessTotal(['Total Amount:\$68.83', 'THANK YOU']);
    expect(r?.amount.minorUnits, 6883);
  });

  test('total above tender block (tendered/change must not win)', () {
    final r = h().guessTotal([
      'Total Amount: \$68.83',
      'TENDERED \$68.83',
      'CASH BACK \$0.00',
      'CHANGE \$0.00',
    ]);
    expect(r?.amount.minorUnits, 6883);
  });

  test('uppercase variant', () {
    final r = h().guessTotal([
      'SUBTOTAL 63.50',
      'SALES TAX 5.33',
      'TOTAL AMOUNT: 68.83',
      'ITEMS SOLD 2',
    ]);
    expect(r?.amount.minorUnits, 6883);
  });
}
