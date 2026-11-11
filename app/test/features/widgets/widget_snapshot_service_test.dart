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

// E7c §4.2 — the Dart writer over a real in-memory repo: schema-complete
// payloads, tightest-envelope-first ordering, engine-honest totals and the
// debounced churn pipeline. Flavor-neutral (the service is pro-wired but
// pure), so it runs in the free suite like all analytics math.
import 'dart:convert';
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/widgets/widget_snapshot_service.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  DateTime clock() => DateTime(2026, 11, 10, 12);

  late AppDatabase db;
  late LedgerRepository repo;
  late List<String> published;
  late WidgetSnapshotService service;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    published = [];
    service = WidgetSnapshotService(
      repository: repo,
      sink: (j) async => published.add(j),
      clock: clock,
      debounce: const Duration(seconds: 30), // tests flush manually
    );
  });
  tearDown(() async => db.close());

  Future<int> category(String key) =>
      repo.addCategory(key, icon: key.toLowerCase());

  Future<void> spend({
    required int catId,
    required DateTime date,
    required int minor,
    bool isIncome = false,
  }) async {
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: date,
      amount: Money(minor, usd),
      source: TransactionSource.manual,
      categoryId: catId,
      isIncome: isIncome,
    );
  }

  Future<WidgetSnapshot> build() async => decodeWidgetSnapshot(
    utf8.encode(await service.buildSnapshot()),
  );

  test('aggregates, budget frame and privacy-only keys', () async {
    final groceries = await category('Groceries');
    final fun = await category('Fun');
    final misc = await category('Misc'); // unbudgeted
    await repo.setBudget(
      categoryId: groceries,
      yearMonth: '2026-11',
      limitMinor: 20000,
      currencyCode: 'USD',
    );
    await repo.setBudget(
      categoryId: fun,
      yearMonth: '2026-11',
      limitMinor: 5000,
      currencyCode: 'USD',
    );
    await spend(catId: groceries, date: DateTime(2026, 11, 3), minor: 7900);
    await spend(catId: fun, date: DateTime(2026, 11, 5), minor: 5800);
    await spend(catId: misc, date: DateTime(2026, 11, 6), minor: 3000);
    await spend(
      catId: groceries,
      date: DateTime(2026, 11, 7),
      minor: 900,
      isIncome: true,
    ); // income never spends
    await spend(catId: groceries, date: DateTime(2026, 10, 30), minor: 1234); //
    // last month is invisible to the frame

    final s = await build();
    expect(s.yearMonth, '2026-11');
    expect(s.currency, 'USD');
    expect(s.updatedAtMs, clock().millisecondsSinceEpoch);
    expect(s.spentMinor, 7900 + 5800 + 3000); // unbudgeted in, income out
    expect(s.budgetSpentMinor, 7900 + 5800); // no overall target → sum of lines
    expect(s.budgetLimitMinor, 25000);
    // Tightest first — the overspent "Fun" leads, exactly like the sheet.
    expect(
      s.envelopes.map((e) => (e.name, e.remainingMinor)).toList(),
      [('Fun', -800), ('Groceries', 12100)],
    );
    // §4.4: the wire document holds nothing but the allow-list.
    expect(
      (jsonDecode(await service.buildSnapshot()) as Map).keys.toList(),
      widgetSnapshotKeys,
    );
  });

  test('overall target replaces the envelope sum', () async {
    final groceries = await category('Groceries');
    await repo.setBudget(
      categoryId: groceries,
      yearMonth: '2026-11',
      limitMinor: 20000,
      currencyCode: 'USD',
    );
    await repo.setBudget(
      categoryId: null, // the overall target row
      yearMonth: '2026-11',
      limitMinor: 50000,
      currencyCode: 'USD',
    );
    await spend(catId: groceries, date: DateTime(2026, 11, 2), minor: 7900);

    final s = await build();
    expect(s.budgetLimitMinor, 50000);
    // overall target counts everything that counts toward budgets:
    expect(s.budgetSpentMinor, 7900);
    expect(s.spentMinor, 7900);
  });

  test('empty month publishes a zero frame, never an absent file', () async {
    final s = await build();
    expect(s.yearMonth, '2026-11');
    expect(s.spentMinor, 0);
    expect(s.budgetLimitMinor, 0);
    expect(s.envelopes, isEmpty);
  });

  test('start publishes at once; ledger churn debounces behind the timer', () async {
    service.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(published.length, 1); // cold-start write

    final groceries = await category('Groceries');
    await spend(catId: groceries, date: DateTime(2026, 11, 4), minor: 100);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(published.length, 1); // still coalescing (30 s debounce)

    await service.flush();
    expect(published.length, 2); // manual flush wins the race
    service.stop();
  });

  test('resume re-arms the stream after the month rolls over', () async {
    var now = DateTime(2026, 11, 30, 23, 58);
    final rolling = WidgetSnapshotService(
      repository: repo,
      sink: (_) async {},
      clock: () => now,
    );
    rolling.start();
    rolling.stop(); // we only assert the build target below

    now = DateTime(2026, 12, 1, 0, 1); // past midnight, new month
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: DateTime(2026, 12, 1),
      amount: Money(500, usd),
      source: TransactionSource.manual,
      categoryId: null,
    );
    final json = await rolling.buildSnapshot();
    final s = decodeWidgetSnapshot(utf8.encode(json) as dynamic);
    expect(s.yearMonth, '2026-12');
    expect(s.spentMinor, 500);
    rolling.stop();
  });
}
