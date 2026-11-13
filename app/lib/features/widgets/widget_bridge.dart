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
