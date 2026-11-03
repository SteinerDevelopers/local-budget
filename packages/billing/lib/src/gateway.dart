/// The billing seam — spec §4. Implemented twice: the app-layer
/// `in_app_purchase` adapter (Android/Play) and [FakeBillingGateway]
/// (tests, `--dart-define=FAKE_BILLING=true` dev builds).
///
/// Consumable-only by design (v2 §4): `pastPurchases` died with the unlock
/// product; do not resurrect a "what do I own" surface — entitlements come
/// from the installed SKU (`FeatureFlags.pro`), never from billing.
library;

import 'models.dart';

abstract class BillingGateway {
  /// Idempotent connect; failures throw — callers degrade per §6.
  Future<void> connect();

  /// Catalog lookup; an empty list means "unavailable" (§6), a throw means
  /// unreachable store (§6).
  Future<List<BillingProduct>> products(List<String> ids);

  /// Starts one purchase. Results arrive on [events] only — this future just
  /// reports launch failures.
  Future<void> buy(String productId);

  /// Confirms consumption after the thank-you receipt was persisted durably.
  Future<void> ack(PurchaseInfo purchase);

  /// Lifetime broadcast stream of purchase progress (§4).
  Stream<PurchaseEvent> get events;

  /// Play account country (billing config), `null` when unknown/absent —
  /// drives the §7 region gate.
  Future<String?> accountCountry();

  Future<void> close();
}

/// The sliver of the settings store TipService needs (the `Settings` kv
/// table via `LedgerRepository`); keeps this package dependency-free.
abstract class SettingsKv {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
