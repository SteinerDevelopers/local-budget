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

import 'dart:async';

import 'package:billing/billing.dart';
import 'package:test/test.dart';

class MemKv implements SettingsKv {
  final map = <String, String>{};

  @override
  Future<String?> get(String key) async => map[key];

  @override
  Future<void> set(String key, String value) async => map[key] = value;
}

void main() {
  late FakeBillingGateway gateway;
  late MemKv kv;
  late TipService tips;

  setUp(() {
    gateway = FakeBillingGateway();
    kv = MemKv();
    tips = TipService(gateway: gateway, kv: kv);
  });
  tearDown(() async {
    await tips.dispose();
    await gateway.close();
  });

  group('catalog', () {
    test('three coffees with store prices', () async {
      final catalog = await tips.catalog();
      expect(catalog.map((p) => p.id), TipService.coffeeProducts);
      expect(catalog.first.price, '\$2.99');
    });

    test('store unreachable is the caller\'s §6 state', () async {
      final g = FakeBillingGateway(productsThrow: true);
      final t = TipService(gateway: g, kv: kv);
      await expectLater(t.catalog(), throwsStateError);
      await t.dispose();
    });
  });

  group('tip', () {
    test('happy path: event, receipt, ack', () async {
      final r = await tips.tip('lb_coffee_small');
      expect(r.outcome, PurchaseOutcome.purchased);
      expect(kv.map[TipService.keyTips], 'lb_coffee_small');
      expect(gateway.acked.single.purchaseToken, 'tok-lb_coffee_small');
      expect(gateway.buyCount, 1);
    });

    test('pending then late completion badges without UI', () async {
      final g = FakeBillingGateway(
        buyScript: const [PurchaseEvent(PurchaseOutcome.pending)],
      );
      final t = TipService(gateway: g, kv: kv);
      final r = await t.tip('lb_coffee_medium');
      expect(r.outcome, PurchaseOutcome.pending);
      expect(kv.map, isEmpty);
      g.emit(
        const PurchaseEvent(
          PurchaseOutcome.purchased,
          purchase: PurchaseInfo(
              productId: 'lb_coffee_medium', purchaseToken: 'tok-late'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(kv.map[TipService.keyTips], 'lb_coffee_medium');
      expect(g.acked.single.pending, isFalse);
      await t.dispose();
    });

    test('canceled is silent, nothing recorded', () async {
      final g = FakeBillingGateway(
        buyScript: const [PurchaseEvent(PurchaseOutcome.canceled)],
      );
      final t = TipService(gateway: g, kv: kv);
      final r = await t.tip('lb_coffee_small');
      expect(r.outcome, PurchaseOutcome.canceled);
      expect(kv.map, isEmpty);
      expect(g.acked, isEmpty);
      await t.dispose();
    });

    test('error passes the store message through', () async {
      final g = FakeBillingGateway(
        buyScript: const [
          PurchaseEvent(PurchaseOutcome.error, message: 'billing off'),
        ],
      );
      final t = TipService(gateway: g, kv: kv);
      final r = await t.tip('lb_coffee_small');
      expect(r.outcome, PurchaseOutcome.error);
      expect(r.message, 'billing off');
      await t.dispose();
    });

    test('single-flight: second tap cannot double-charge', () async {
      final g = FakeBillingGateway(buyScript: const []); // never resolves
      final t = TipService(gateway: g, kv: kv);
      final first = t.tip('lb_coffee_small');
      await Future<void>.delayed(Duration.zero);
      final second = await t.tip('lb_coffee_large');
      expect(second.outcome, PurchaseOutcome.error);
      expect(second.message, 'tip already in progress');
      expect(g.buyCount, 1);
      g.emit(
        const PurchaseEvent(
          PurchaseOutcome.purchased,
          purchase: PurchaseInfo(
              productId: 'lb_coffee_small', purchaseToken: 'tok-x'),
        ),
      );
      expect((await first).outcome, PurchaseOutcome.purchased);
      await t.dispose();
    });
  });

  group('receipt', () {
    test('tips accumulate oldest first, duplicates never double', () async {
      await tips.tip('lb_coffee_small');
      await tips.tip('lb_coffee_large');
      expect(await tips.tipsAcked(), ['lb_coffee_small', 'lb_coffee_large']);
      gateway.emit(
        const PurchaseEvent(
          PurchaseOutcome.purchased,
          purchase: PurchaseInfo(
              productId: 'lb_coffee_small', purchaseToken: 'tok-again'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await tips.tipsAcked(), ['lb_coffee_small', 'lb_coffee_large']);
    });

    test('unknown products are ignored', () async {
      gateway.emit(
        const PurchaseEvent(
          PurchaseOutcome.purchased,
          purchase: PurchaseInfo(productId: 'lb_mystery', purchaseToken: 't'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await tips.tipsAcked(), isEmpty);
      expect(gateway.acked, isEmpty);
    });
  });

  // Spec §8: the invariant, pinned. Billing must never carry an unlock.
  group('invariant — no unlock product can exist', () {
    test('catalog and constants contain nothing named unlock', () {
      for (final p in FakeBillingGateway.defaultCatalog) {
        expect(p.id.contains('unlock'), isFalse);
      }
      expect(
        TipService.coffeeProducts.any((id) => id.contains('unlock')),
        isFalse,
      );
    });
  });
}
