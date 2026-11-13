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

// E6 §5/§6 — the coffee sheet driven from the real widget tree over the
// [FakeBillingGateway] seam (§4): catalog chips, every purchase outcome,
// the degraded phases, and the durable receipt. No store, no network.
//
// Same drift rules as manage_test.dart: db.close() inside tearDown; every
// SnackBar gets expired (fake-async leaves its 4 s timer pending).
import 'dart:ffi';

import 'package:billing/billing.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/help/help_articles.dart';
import 'package:local_budget/features/manage/manage_screen.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class _MemKv implements SettingsKv {
  final map = <String, String>{};

  @override
  Future<String?> get(String key) async => map[key];

  @override
  Future<void> set(String key, String value) async => map[key] = value;
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late AppDatabase db;
  late LedgerRepository repo;
  late TipService? held;

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    await repo.ensureDefaults();
    held = null;
  });

  tearDown(() async {
    await held?.dispose();
    await db.close();
  });

  /// Opens Manage, scrolls to the Support section (E6 §5 grew the list —
  /// same viewport rule as manage_test's scrollToBottom) and taps the
  /// coffee row with [service] wired through.
  Future<TipService?> openCoffee(
    WidgetTester tester, {
    TipService Function(_MemKv kv)? service,
  }) async {
    final kv = _MemKv();
    final svc = service?.call(kv);
    held = svc;
    await tester.pumpWidget(
      MaterialApp(
        home: ManageScreen(repository: repo, tips: svc),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('coffee')),
      find.byType(ListView).last,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coffee')));
    await tester.pumpAndSettle();
    return svc;
  }

  Future<void> expireSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  TipService svcFor(BillingGateway gateway, SettingsKv kv) =>
      TipService(gateway: gateway, kv: kv);

  testWidgets('the sheet sells three coffees and one lands', (tester) async {
    final gateway = FakeBillingGateway();
    final svc = (await openCoffee(
      tester,
      service: (kv) => TipService(gateway: gateway, kv: kv),
    ))!;

    expect(
      find.byKey(const Key('coffee-chip-lb_coffee_small')),
      findsOneWidget,
    );
    expect(find.text('\$2.99'), findsOneWidget);
    expect(find.text('\$14.99'), findsOneWidget);
    expect(find.byKey(const Key('coffee-receipts')), findsNothing);

    await tester.tap(find.byKey(const Key('coffee-buy')));
    await tester.pumpAndSettle();

    // The middle coffee is the default — buying needs one tap after open.
    expect(gateway.bought, ['lb_coffee_medium']);
    expect(find.text('Thank you! ☕'), findsOneWidget);
    expect(
      find.textContaining(
        'Tips unlock nothing — they just keep the '
        'lights on.',
      ),
      findsOneWidget,
    );
    // §4: the receipt is durable (kv) before the ack goes to the store.
    expect(await svc.tipsAcked(), ['lb_coffee_medium']);
    expect(gateway.acked.map((p) => p.purchaseToken), ['tok-lb_coffee_medium']);

    await tester.tap(find.byKey(const Key('coffee-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('a past tip is remembered as a receipt line', (tester) async {
    final gateway = FakeBillingGateway();
    await openCoffee(
      tester,
      service: (kv) {
        kv.map[TipService.keyTips] = 'lb_coffee_small';
        return svcFor(gateway, kv);
      },
    );
    expect(
      find.text('You bought me a coffee once. Thank you.'),
      findsOneWidget,
    );
  });

  testWidgets('pending says processing, never purchased (§6)', (tester) async {
    final gateway = FakeBillingGateway(
      buyScript: [PurchaseEvent(PurchaseOutcome.pending)],
    );
    final svc = (await openCoffee(
      tester,
      service: (kv) => TipService(gateway: gateway, kv: kv),
    ))!;

    await tester.tap(find.byKey(const Key('coffee-buy')));
    await tester.pumpAndSettle();

    expect(
      find.text('Tip is processing — thank you either way.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('coffee-thanks')), findsNothing);
    expect(await svc.tipsAcked(), isEmpty);
    expect(gateway.acked, isEmpty);
    await expireSnack(tester);
  });

  testWidgets('a cancelled tip is silent (§6)', (tester) async {
    final gateway = FakeBillingGateway(
      buyScript: [PurchaseEvent(PurchaseOutcome.canceled)],
    );
    await openCoffee(
      tester,
      service: (kv) => TipService(gateway: gateway, kv: kv),
    );

    await tester.tap(find.byKey(const Key('coffee-buy')));
    await tester.pumpAndSettle();

    // Back on the chips, no snack, no receipt, nothing charged.
    expect(find.text('Buy the coffee'), findsOneWidget);
    expect(find.byKey(const Key('coffee-thanks')), findsNothing);
    expect(find.textContaining('processing'), findsNothing);
    expect(gateway.bought, ['lb_coffee_medium']);
    expect(gateway.acked, isEmpty);
  });

  testWidgets('store unreachable degrades with the §6 copy', (tester) async {
    final gateway = FakeBillingGateway(connectFails: true);
    await openCoffee(
      tester,
      service: (kv) => TipService(gateway: gateway, kv: kv),
    );
    expect(find.text("Can't take a tip right now."), findsOneWidget);
    expect(
      find.text("Can't reach the store right now — try again later."),
      findsOneWidget,
    );
  });

  testWidgets('an empty catalog is honest, not broken', (tester) async {
    final gateway = FakeBillingGateway(products: []);
    await openCoffee(
      tester,
      service: (kv) => TipService(gateway: gateway, kv: kv),
    );
    expect(find.text("Can't take a tip right now."), findsOneWidget);
    expect(
      find.text("Tipping isn't available in your store yet."),
      findsOneWidget,
    );
  });

  testWidgets('no billing layer explains itself instead of dying', (
    tester,
  ) async {
    await openCoffee(tester); // tips == null — host builds, iOS, tests
    expect(find.text('Tips need the real app.'), findsOneWidget);
    expect(
      find.text('The store billing layer is not part of this build.'),
      findsOneWidget,
    );
  });

  test('E6 functions are in the searchable help (§ help mandate)', () {
    expect(
      searchHelpArticles('coffee').map((a) => a.title),
      contains('Buy me a coffee'),
    );
    expect(
      searchHelpArticles('tip').map((a) => a.title),
      contains('Buy me a coffee'),
    );
    expect(
      searchHelpArticles('transfer').map((a) => a.title),
      contains('Upgrading to Pro, and copying your data'),
    );
    expect(
      searchHelpArticles('upgrade').map((a) => a.title),
      contains('Upgrading to Pro, and copying your data'),
    );
    // Voice bar: the free app never promises an unlock inside itself.
    for (final a in kHelpArticles) {
      expect(a.haystack, isNot(contains('unlock ')), reason: a.title);
    }
  });
}
