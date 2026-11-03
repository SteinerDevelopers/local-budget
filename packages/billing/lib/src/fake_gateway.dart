/// Scriptable fake — spec §4. Ships in the package so app widget tests and
/// dev builds (`--dart-define=FAKE_BILLING=true`) drive every state without
/// a store.
library;

import 'dart:async';

import 'gateway.dart';
import 'models.dart';

class FakeBillingGateway implements BillingGateway {
  FakeBillingGateway({
    List<BillingProduct>? products,
    this.country = 'US',
    this.connectFails = false,
    this.productsThrow = false,
    List<PurchaseEvent>? buyScript,
  })  : _products = products ?? defaultCatalog,
        _buyScript = buyScript;

  static const defaultCatalog = [
    BillingProduct(
        id: 'lb_coffee_small', title: 'Small coffee', price: '\$2.99'),
    BillingProduct(
        id: 'lb_coffee_medium', title: 'Large coffee', price: '\$6.99'),
    BillingProduct(
        id: 'lb_coffee_large', title: 'Coffee for the team', price: '\$14.99'),
  ];

  final List<BillingProduct> _products;
  final List<PurchaseEvent>? _buyScript;

  final String? country;
  final bool connectFails;
  final bool productsThrow;

  int connectCount = 0;
  int buyCount = 0;
  final acked = <PurchaseInfo>[];
  final bought = <String>[];

  final _ctrl = StreamController<PurchaseEvent>.broadcast();

  /// Inject an event from outside the buy() script (late pending completion).
  void emit(PurchaseEvent ev) => _ctrl.add(ev);

  @override
  Future<void> connect() async {
    connectCount++;
    if (connectFails) throw StateError('billing unavailable');
  }

  @override
  Future<List<BillingProduct>> products(List<String> ids) async {
    if (productsThrow) throw StateError('store unreachable');
    return _products.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<void> buy(String productId) async {
    buyCount++;
    bought.add(productId);
    final script = _buyScript ??
        [
          PurchaseEvent(
            PurchaseOutcome.purchased,
            purchase: PurchaseInfo(
                productId: productId, purchaseToken: 'tok-$productId'),
          ),
        ];
    for (final ev in script) {
      scheduleMicrotask(() => _ctrl.add(ev));
    }
  }

  @override
  Future<void> ack(PurchaseInfo purchase) async => acked.add(purchase);

  @override
  Stream<PurchaseEvent> get events => _ctrl.stream;

  @override
  Future<String?> accountCountry() async => country;

  @override
  Future<void> close() => _ctrl.close();
}
