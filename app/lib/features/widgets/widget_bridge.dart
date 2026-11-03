import 'package:flutter/services.dart';

/// Dart client for the widget bridge (`dev.steiner.local_budget/widget`).
/// Thin on purpose: the aggregates live in [WidgetSnapshotService], the
/// file lives in Kotlin — this class is just the wire both ways.
///
/// Publishing returns Kotlin's write verdict; a rejected write throws so
/// the service's swallow-and-retry path engages (the next ledger write or
/// resume re-publishes — no state to reconcile, the file is rebuildable).
class WidgetBridge {
  static const MethodChannel _channel = MethodChannel(
    'dev.steiner.local_budget/widget',
  );

  static Future<void> publish(String json) async {
    final ok = await _channel.invokeMethod<bool>('publish', {'json': json});
    if (ok != true) {
      throw StateError('widget snapshot publish rejected');
    }
  }

  /// Consume the pending widget tap, if any (cold start and warm pushes
  /// both land here — exactly-once navigation falls out of the clear).
  static Future<String?> takeRoute() async {
    try {
      return await _channel.invokeMethod<String>('takeRoute');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Tests, goldens, non-Android boots: no widgets, no routes.
      return null;
    }
  }

  /// Warm pushes while the engine lives; the payload string is a hint —
  /// the handler re-reads via [takeRoute] so mailbox and push can't race
  /// into a double navigation.
  static void onRoute(void Function(String route) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'route') return;
      final route = await takeRoute();
      if (route != null) handler(route);
    });
  }
}
