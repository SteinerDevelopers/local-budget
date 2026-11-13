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
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:test/test.dart';

/// v6 adds transactions.externalId + the partial unique index that makes
/// OFX FITID dedupe enforced by the database (E5 §5). Shipped v5 installs
/// lack both; this rewinds a current database to the exact v5 shape and
/// verifies the open upgrades it back — re-runnable via the same
/// PRAGMA table_info guard the other steps use.
void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('budget_mig_v6');
    path = '${tmp.path}/ledger.sqlite';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'a shipped v5 install gains external_id + the index, keeps rows',
    () async {
      // A current install with real data...
      final db1 = AppDatabase.openFile(path);
      final repo1 = LedgerRepository(db1);
      final accountId = await repo1.createAccount(
        name: 'Checking',
        currencyCode: 'USD',
      );
      await repo1.addTransaction(
        accountId: accountId,
        date: DateTime.utc(2026, 10, 9),
        amount: Money(1299, Currency.resolve('USD')),
        source: TransactionSource.statementImport,
        externalId: 'FITID-KEEP',
      );
      await repo1.addTransaction(
        accountId: accountId,
        date: DateTime.utc(2026, 10, 10),
        amount: Money(500, Currency.resolve('USD')),
        source: TransactionSource.manual,
      );
      await db1.close();

      // ...rewound to the shipped v5 shape: no external_id, no index,
      // version pinned. (Dropping the column would strand the index, so
      // SQLite only allows it after the index goes.)
      final raw = raw_sqlite3.sqlite3.open(path);
      raw.execute('DROP INDEX tx_account_external');
      raw.execute('ALTER TABLE transactions DROP COLUMN external_id');
      raw.execute('PRAGMA user_version = 5');
      raw.dispose();

      final db2 = AppDatabase.openFile(path);
      final repo2 = LedgerRepository(db2);
      addTearDown(db2.close);

      expect(
        (await db2.customSelect('PRAGMA user_version').getSingle())
            .data['user_version'],
        6,
      );
      final cols = await db2
          .customSelect("PRAGMA table_info('transactions')")
          .get();
      expect(cols.map((r) => r.data['name']), contains('external_id'));
      final idx = await db2
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'tx_account_external'",
          )
          .get();
      expect(idx, hasLength(1));
      expect(idx.single.data['sql'], contains('WHERE external_id IS NOT NULL'));

      // Rows survived the round trip; the old FITID is gone with the column
      // (dedupe keys restart at the upgrade — accepted, documented).
      final rows = await db2.select(db2.transactions).get();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.externalId), everyElement(isNull));

      // The write path works and the index is enforced again: a repeat
      // FITID on the same account is rejected by the database itself.
      await repo2.addTransaction(
        accountId: accountId,
        date: DateTime.utc(2026, 11, 2),
        amount: Money(350, Currency.resolve('USD')),
        source: TransactionSource.statementImport,
        externalId: 'FITID-NEW',
      );
      await expectLater(
        repo2.addTransaction(
          accountId: accountId,
          date: DateTime.utc(2026, 11, 2),
          amount: Money(350, Currency.resolve('USD')),
          source: TransactionSource.statementImport,
          externalId: 'FITID-NEW',
        ),
        throwsA(isA<Object>()),
      );
      expect(
        db2
            .select(db2.transactions)
            .get()
            .then(
              (rows) => rows.where((r) => r.externalId == 'FITID-NEW').length,
            ),
        completion(1),
      );
    },
  );

  test(
    'the migration is idempotent (open twice on the upgraded file)',
    () async {
      final db1 = AppDatabase.openFile(path);
      // Drift migrates lazily on first access — force the v6 schema into
      // the file before rewinding, otherwise this would replay the step
      // against an empty database.
      await db1.customSelect('PRAGMA user_version').getSingle();
      await db1.close();
      final raw = raw_sqlite3.sqlite3.open(path);
      raw.execute('PRAGMA user_version = 5');
      raw.dispose();
      final db2 = AppDatabase.openFile(
        path,
      ); // from<6 step re-runs on a v6 file
      addTearDown(db2.close);
      expect(
        (await db2.customSelect('PRAGMA user_version').getSingle())
            .data['user_version'],
        6,
      );
    },
  );
}
