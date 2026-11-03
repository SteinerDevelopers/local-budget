/// Coffee tips — spec §2/§4. The entire monetization surface of the free
/// app. Grants: a thank-you badge. Locks nothing, unlocks nothing (§0).
library;

import 'dart:async';

import 'gateway.dart';
import 'models.dart';

class TipService {
  TipService({required this.gateway, required this.kv}) {
    _events = gateway.events.listen(_onEvent);
  }

  /// Product ids are permanent (spec §2) — consumable donations.
  static const coffeeProducts = <String>[
    'lb_coffee_small',
    'lb_coffee_medium',
    'lb_coffee_large',
  ];

  static const keyTips = 'tips_acked';

  final BillingGateway gateway;
  final SettingsKv kv;

  late final StreamSubscription<PurchaseEvent> _events;
  bool _tipInFlight = false;
  Future<void> _queue = Future.value();

  /// The three coffees, store-localized (§5). Throws are the caller's §6
  /// "store unreachable" state — the sheet degrades, nothing else cares.
  Future<List<BillingProduct>> catalog() => gateway.products(coffeeProducts);

  /// Launches a tip and returns the first event for UI copy (§6). A
  /// `pending` sale that completes later is recorded by the lifetime
  /// listener — no UI needed, the badge just appears next visit.
  Future<BuyResult> tip(String productId) async {
    if (_tipInFlight) {
      return const BuyResult(
        PurchaseOutcome.error,
        message: 'tip already in progress',
      );
    }
    _tipInFlight = true;
    try {
      final first = gateway.events.first;
      await gateway.buy(productId);
      final ev = await first;
      // The lifetime listener is registered first, so its chain is already
      // enqueued here; draining it makes the receipt durable by the time the
      // UI shows a thank-you.
      await _queue;
      return BuyResult(ev.outcome, message: ev.message);
    } finally {
      _tipInFlight = false;
    }
  }

  /// Completed tip ids, oldest first (thank-you receipt line, §5).
  Future<List<String>> tipsAcked() async {
    final raw = await kv.get(keyTips);
    return raw == null || raw.isEmpty ? const [] : raw.split(',');
  }

  Future<void> dispose() async {
    await _events.cancel();
  }

  /// Serializes receipt work: events processed one at a time, in order; a
  /// broken kv write must never poison the queue.
  void _onEvent(PurchaseEvent ev) {
    _queue = _queue.then((_) => _record(ev)).catchError((Object _) {});
  }

  Future<void> _record(PurchaseEvent ev) async {
    if (ev.outcome != PurchaseOutcome.purchased) return;
    final p = ev.purchase;
    if (p == null || p.pending) return;
    if (!coffeeProducts.contains(p.productId)) return;
    final acked = await tipsAcked();
    if (!acked.contains(p.productId)) {
      await kv.set(keyTips, [...acked, p.productId].join(','));
    }
    try {
      await gateway.ack(p);
    } on Object {
      // An unacked consumable reappears on the purchase stream; the kv write
      // above is idempotent, so the receipt cannot double-count (§4).
    }
  }
}
