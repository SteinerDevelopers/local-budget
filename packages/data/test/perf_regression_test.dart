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

import 'dart:ffi';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart' show NativeDatabase;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

/// Hardening #23: perf regression floor for the ledger month page. A
/// local-first budget app never prunes history, so the month query must
/// stay index-backed as the table grows — this test is the tripwire if a
/// future change drops the index or rewrites watchMonth into a scan+sort.
void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  test('upgrade from schema v2 adds tx_date (dev installs survive)', () async {
    final path =
        '${Directory.systemTemp.createTempSync('budget_v2').path}/ledger.db';
    // A v3 database, forcibly rewound to the v2 state (index gone,
    // user_version 2 — every other v2 element already matches).
    final db1 = AppDatabase.openFile(path);
    await db1.customStatement('DROP INDEX tx_date');
    await db1.customStatement('PRAGMA user_version = 2');
    await db1.close();

    // Reopen exactly like the app after an app update: onUpgrade must fire.
    final db2 = AppDatabase(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final indexes = await db2
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'tx_date'",
        )
        .get();
    expect(indexes, hasLength(1));
  });

  test('EXPLAIN: month range query uses the tx_date index', () async {
    // Mirrors the SQL drift issues for watchMonth's WHERE/ORDER BY (join
    // omitted — the plan for the driving table is what matters here).
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT * FROM transactions '
          'WHERE date_days BETWEEN ? AND ? ORDER BY date_days DESC, id DESC',
          variables: [Variable.withInt(20400), Variable.withInt(20431)],
        )
        .get();
    final plan = rows.map((r) => '${r.data['detail']}').join('\n');
    expect(plan, contains('tx_date'));
    expect(plan, isNot(contains('USE TEMP B-TABLE')));
  });

  test(
    '5,000-transaction month page: seed + first emission within budget',
    () async {
      await repo.ensureDefaults();
      final account = await repo.defaultAccount();

      // 5k rows spread over Jan–Jun 2026 (~28/day), March fully covered.
      final day0 = DateTime.utc(2026, 1, 1);
      final watch = Stopwatch()..start();
      await db.batch((b) {
        b.insertAll(
          db.transactions,
          List.generate(5000, (i) {
            final day = day0.add(Duration(days: i % 181));
            return TransactionsCompanion.insert(
              accountId: account.id,
              dateDays: epochDayOf(day),
              amountMinor: 100 + (i % 9000),
              currencyCode: 'USD',
              source: TransactionSource.manual,
            );
          }),
        );
      });
      watch.stop();
      // Batched insert of the whole corpus: generous 5 s CI budget.
      expect(
        watch.elapsedMilliseconds,
        lessThan(5000),
        reason: 'seeding 5k rows took ${watch.elapsedMilliseconds} ms',
      );

      // First reactive emission = full query + projection mapping.
      watch
        ..reset()
        ..start();
      final march = await repo.watchMonth('2026-03').first;
      watch.stop();
      // 5000 = 27 full 181-day cycles + 113 head days; March (day-of-range
      // 59..89) sits inside the head, so all 31 days carry 28 rows each.
      expect(march.length, 31 * 28);
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'watchMonth mapped in ${watch.elapsedMilliseconds} ms',
      );
    },
  );
}
