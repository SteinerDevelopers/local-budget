import 'dart:async';

import 'package:billing/billing.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    show InAppPurchasePlatform;

/// The one and only file allowed to touch `in_app_purchase` (spec §4): Play
/// Billing types enter here and leave as `billing` models. Everything above
/// — TipService, sheets, Manage — is plugin-agnostic and testable with
/// `FakeBillingGateway`.
///
/// Only coffee consumables exist in this app (spec §0), so only the
/// consumable half of the plugin is bridged; there is no non-consumable call
/// site to reach by accident.
class InAppPurchaseGateway implements BillingGateway {
  /// Product details cached from the last [products] call — `buy` needs the
  /// platform object, and the sheet always shows a catalog before it can buy.
  final Map<String, iap.ProductDetails> _details = {};

  /// Last stream object per purchase token — [ack] must hand the *same*
  /// platform object back to `completePurchase`.
  final Map<String, iap.PurchaseDetails> _purchases = {};

  StreamController<PurchaseEvent>? _relay;
  StreamSubscription<List<iap.PurchaseDetails>>? _source;

  @override
  Future<void> connect() async {
    if (!await iap.InAppPurchase.instance.isAvailable()) {
      throw StateError('billing unavailable');
    }
    if (_relay == null) {
      final relay = StreamController<PurchaseEvent>.broadcast();
      _source = iap.InAppPurchase.instance.purchaseStream.listen(
        (batch) {
          for (final pd in batch) {
            // On Play, `serverVerificationData` is the purchase token.
            _purchases[pd.verificationData.serverVerificationData] = pd;
            relay.add(_map(pd));
          }
        },
        onError: (Object e) => relay.add(
          const PurchaseEvent(
            PurchaseOutcome.error,
            message: 'billing stream error',
          ),
        ),
      );
      _relay = relay;
    }
  }

  @override
  Stream<PurchaseEvent> get events =>
      (_relay ??= StreamController<PurchaseEvent>.broadcast()).stream;

  @override
  Future<List<BillingProduct>> products(List<String> ids) async {
    final response = await iap.InAppPurchase.instance.queryProductDetails(
      ids.toSet(),
    );
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    _details.clear();
    final out = <BillingProduct>[];
    for (final p in response.productDetails) {
      if (!ids.contains(p.id)) continue;
      _details[p.id] = p;
      out.add(BillingProduct(id: p.id, title: p.title, price: p.price));
    }
    return out;
  }

  @override
  Future<void> buy(String productId) async {
    final detail = _details[productId];
    if (detail == null) {
      throw StateError('product $productId not in catalog');
    }
    final ok = await iap.InAppPurchase.instance.buyConsumable(
      purchaseParam: iap.PurchaseParam(productDetails: detail),
    );
    if (!ok) {
      // The launch itself failed (no billing activity started); the outcome
      // never reaches the stream. TipService's `.first` will hang until the
      // sheet's own lifecycle ends — surface it as an immediate error event.
      _relay?.add(
        PurchaseEvent(
          PurchaseOutcome.error,
          purchase: PurchaseInfo(
            productId: productId,
            purchaseToken: 'launch-failed',
            pending: false,
          ),
          message: 'purchase could not start',
        ),
      );
    }
  }

  @override
  Future<void> ack(PurchaseInfo purchase) async {
    final pd = _purchases[purchase.purchaseToken];
    if (pd == null || !pd.pendingCompletePurchase) return;
    await iap.InAppPurchase.instance.completePurchase(pd);
  }

  @override
  Future<String?> accountCountry() async {
    // §7's region gate only; a missing/failed lookup simply hides the
    // link-out row (SupportPolicy treats unknown as hidden unless debug).
    try {
      final code = await InAppPurchasePlatform.instance.countryCode();
      return code.trim().toUpperCase();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() async {
    await _source?.cancel();
    _source = null;
    await _relay?.close();
    _relay = null;
  }

  PurchaseEvent _map(iap.PurchaseDetails pd) {
    final token = pd.verificationData.serverVerificationData;
    // `pending` here is the *sale* state (Play holds/delayed payments) —
    // TipService records + acks completed purchases only. Play's separate
    // `pendingCompletePurchase` is an ack to-do, handled in [ack], and must
    // not masquerade as an unfinished sale or receipts would never land.
    final purchase = PurchaseInfo(
      productId: pd.productID,
      purchaseToken: token,
      pending: pd.status == iap.PurchaseStatus.pending,
    );
    return switch (pd.status) {
      iap.PurchaseStatus.pending => PurchaseEvent(
        PurchaseOutcome.pending,
        purchase: purchase,
      ),
      iap.PurchaseStatus.purchased || iap.PurchaseStatus.restored =>
        PurchaseEvent(PurchaseOutcome.purchased, purchase: purchase),
      iap.PurchaseStatus.canceled => const PurchaseEvent(
        PurchaseOutcome.canceled,
      ),
      iap.PurchaseStatus.error => PurchaseEvent(
        PurchaseOutcome.error,
        purchase: purchase,
        message: pd.error?.message ?? 'purchase failed',
      ),
    };
  }
}
