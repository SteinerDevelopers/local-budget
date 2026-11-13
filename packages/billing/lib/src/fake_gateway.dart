// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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
