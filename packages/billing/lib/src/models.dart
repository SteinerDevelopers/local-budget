/// Domain models — spec §2/§4. Store types never cross the seam; the
/// app-layer adapter maps plugin enums into these.
///
/// v2 invariant (§0): nothing here can represent an entitlement. A tip is
/// a tip.
library;

/// A catalog entry as the coffee sheet renders it. [price] is the
/// store-localized string straight from billing (never recomputed — §4.5
/// honesty).
class BillingProduct {
  const BillingProduct(
      {required this.id, required this.title, required this.price});

  final String id;
  final String title;
  final String price;
}

/// A purchase as it crosses the seam. Tips only survive here today;
/// [pending] covers deferred payments (family review).
class PurchaseInfo {
  const PurchaseInfo({
    required this.productId,
    required this.purchaseToken,
    this.pending = false,
  });

  final String productId;
  final String purchaseToken;
  final bool pending;
}

/// Outcome of an in-flight purchase (§4 events).
enum PurchaseOutcome { pending, purchased, canceled, error }

/// One event on the gateway's purchase stream.
class PurchaseEvent {
  const PurchaseEvent(this.outcome, {this.purchase, this.message});

  final PurchaseOutcome outcome;
  final PurchaseInfo? purchase;

  /// Store-side detail; the app maps outcomes to §6 copy, this is only ever
  /// shown for conditions §6 does not enumerate.
  final String? message;
}

/// Result of [TipService.tip] — the value the UI needs to show §6 copy.
class BuyResult {
  const BuyResult(this.outcome, {this.message});

  final PurchaseOutcome outcome;
  final String? message;
}
