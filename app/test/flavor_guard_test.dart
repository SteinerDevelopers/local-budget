import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/flavor.dart';

/// The 2026-11-05 field bounce: CI built `--flavor pro` without
/// `--dart-define=APP_FLAVOR=pro`, and every shipped "pro" kit booted the
/// free tier — invisible to any test that ran without the define. This file
/// is the paired guard. It runs twice in CI:
///   * app-test lane (no define) → asserts the default is free, and
///   * inside package-apk-pro (with the define) → asserts the pro kit the
///     very next line builds would actually carry the paid tier.
void main() {
  test('tier comes from APP_FLAVOR only, and pro means the trio', () {
    if (const String.fromEnvironment('APP_FLAVOR') == 'pro') {
      expect(appFlavorName, 'pro');
      expect(appFlavor, AppFlavor.pro);
      expect(FeatureFlags.proTrio, isTrue);
    } else {
      // Absent or typo'd define → free, always (the safe direction).
      expect(appFlavorName, isNot('pro'));
      expect(FeatureFlags.proTrio, isFalse);
    }
  });
}
