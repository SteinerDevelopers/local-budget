/// E6 monetization v2 (docs/design/e6-monetization.md).
///
/// Pure Dart (testing tier 1). Tips only — the store can never unlock a
/// feature here (§0); the paid tier is a separate SKU gated by
/// `app/lib/flavor.dart`. A test pins the catalog against `unlock` (§8).
library;

export 'src/fake_gateway.dart';
export 'src/gateway.dart';
export 'src/models.dart';
export 'src/support.dart';
export 'src/tip_service.dart';
