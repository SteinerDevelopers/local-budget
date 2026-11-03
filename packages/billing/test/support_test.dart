import 'package:billing/billing.dart';
import 'package:test/test.dart';

void main() {
  group('SupportPolicy (§7)', () {
    test('US sees the link-out', () {
      expect(SupportPolicy.visible('US'), isTrue);
    });
    test('other countries do not', () {
      expect(SupportPolicy.visible('DE'), isFalse);
      expect(SupportPolicy.visible('US'.toLowerCase()), isFalse);
    });
    test('unknown region: hidden in release, visible in debug', () {
      expect(SupportPolicy.visible(null), isFalse);
      expect(SupportPolicy.visible(null, debug: true), isTrue);
    });
  });

  test('BMC link is https and grants nothing new', () {
    expect(SupportLinks.bmc, startsWith('https://'));
  });
}
