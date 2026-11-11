// Plain integration-test driver, kept for the one job `flutter test`
// cannot do on this SDK: running a probe at a chosen build mode
// (`flutter test` has no --profile here, while `flutter drive` does —
// measured 2026-11-10). The jank probe is only meaningful as a profile
// build, so it runs through drive:
//
//   flutter drive --profile --flavor free -d <bench-tablet> \
//     --driver integration_test/driver.dart \
//     --target integration_test/jank_probe_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
