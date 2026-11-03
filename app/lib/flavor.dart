/// E6 §1: the store tier is an Android product flavor, and this file is the
/// *only* way Dart learns about it (`--dart-define=APP_FLAVOR=pro`, paired
/// with `--flavor pro` by the build). No billing state ever unlocks anything
/// (spec §0 invariant) — E7 features read [FeatureFlags.proTrio], never the
/// purchase layer.
library;

enum AppFlavor { free, pro }

/// Build-time name, `free` unless a build says otherwise. A typo can only
/// ever land the app on `free` — the safe direction.
const String appFlavorName = String.fromEnvironment(
  'APP_FLAVOR',
  defaultValue: 'free',
);

const AppFlavor appFlavor = appFlavorName == 'pro'
    ? AppFlavor.pro
    : AppFlavor.free;

abstract final class FeatureFlags {
  /// The decision-9 trio (cloud sync / widgets / insights): these features
  /// ship *inside the Pro SKU* — this flag is a build fact, not an entitlement.
  static bool get proTrio => appFlavor == AppFlavor.pro;
}
