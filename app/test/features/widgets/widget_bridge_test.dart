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
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/widgets/widget_bridge.dart';

/// Wire contract against a fake Kotlin side — the mailbox semantics
/// (§4.1 "exactly once") live here, not in the aggregate tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.steiner.local_budget/widget');
  late List<String?> mailbox; // pending route; empty = none
  late List<String> calls;

  /// What Kotlin does on a warm tap: a platform→Dart 'route' invocation.
  /// (invokeMethod from the test would ride the *outgoing* direction and
  /// hit the mock — this is the real inbound path.)
  Future<void> pushRoute(String route) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('route', route),
            ),
            (_) {},
          );

  setUp(() {
    mailbox = [];
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'publish':
              return true;
            case 'takeRoute':
              return mailbox.isEmpty ? null : mailbox.removeAt(0);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    WidgetBridge.onRoute((_) {});
  });

  test('publish round-trips the JSON and honours the verdict', () async {
    await WidgetBridge.publish('{}'); // ok=true ⇒ no throw
    mailbox.clear();
  });

  test('a rejected write throws so the service retry path engages',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    await expectLater(
      WidgetBridge.publish('{}'),
      throwsA(isA<StateError>()),
    );
  });

  test('takeRoute drains the cold-start mailbox exactly once', () async {
    mailbox.add('reports');
    expect(await WidgetBridge.takeRoute(), 'reports');
    expect(await WidgetBridge.takeRoute(), isNull);
  });

  test('a warm push navigates via the mailbox, not a second copy', () async {
    final seen = <String>[];
    WidgetBridge.onRoute(seen.add);
    mailbox.add('capture');
    // Kotlin's pushRoute: pending set, then invokeMethod('route', hint).
    await pushRoute('capture');
    await pumpEventQueue();
    expect(seen, ['capture']);
    expect(mailbox, isEmpty); // consumed — a boot-time takeRoute finds none
    expect(calls, contains('takeRoute'));
  });

  test('push with an empty mailbox (already drained) navigates nobody',
      () async {
    final seen = <String>[];
    WidgetBridge.onRoute(seen.add);
    await pushRoute('budgets');
    await pumpEventQueue();
    expect(seen, isEmpty);
  });

  test('no platform side at all ⇒ silent null (tests/goldens boot)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await WidgetBridge.takeRoute(), isNull);
  });
}
