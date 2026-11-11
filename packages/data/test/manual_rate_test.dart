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

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

/// E5 §6 — the manual-rate path on the repository: a foreign row saved
/// without a rate is real data; one call stamps the base snapshot from the
/// stored amount through core's audited conversion.
void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  late AppDatabase db;
  late LedgerRepository repo;
  late int accountId;

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    await repo.ensureDefaults();
    accountId = (await repo.defaultAccount()).id;
  });
  tearDown(() => db.close());

  Future<int> addForeignNoRate({int minor = 1000, String code = 'EUR'}) =>
      repo.addTransaction(
        accountId: accountId,
        date: DateTime(2026, 11, 2),
        amount: Money(minor, Currency.resolve(code)),
        source: TransactionSource.manual,
      );

  test(
    'a foreign save without a rate still writes the row, rate-less',
    () async {
      final id = await addForeignNoRate();
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.baseAmountMinor, isNull);
      expect(row.fxRate, isNull);
      expect(row.amountMinor, 1000);
    },
  );

  test(
    'setManualRate snapshots the base amount from the stored value',
    () async {
      final id = await addForeignNoRate();
      await repo.setManualRate(id: id, fxRate: 0.9);
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.fxRate, 0.9);
      // €10.00 at 0.9 — the exact audited number Money.convertTo produces.
      expect(
        row.baseAmountMinor,
        Money(
          1000,
          Currency.resolve('EUR'),
        ).convertTo(Currency.resolve('USD'), 0.9).minorUnits,
      );
    },
  );

  test(
    'the month projection exposes fxRate so the detail sheet can show it',
    () async {
      final id = await addForeignNoRate();
      await repo.setManualRate(id: id, fxRate: 1.0834);
      final rows = await repo.watchMonth('2026-11').first;
      expect(rows.single.fxRate, 1.0834);
      expect(rows.single.baseAmountMinor, isNotNull);
      expect(rows.single.currencyCode, 'EUR');
    },
  );

  test('an existing machine rate can be restamped by hand', () async {
    final id = await repo.addTransaction(
      accountId: accountId,
      date: DateTime(2026, 11, 2),
      amount: Money(1000, Currency.resolve('EUR')),
      source: TransactionSource.manual,
      baseCurrencyCode: 'USD',
      fxRate: 2.0, // wrong-on-purpose
    );
    await repo.setManualRate(id: id, fxRate: 1.1);
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.fxRate, 1.1);
    expect(
      row.baseAmountMinor,
      Money(
        1000,
        Currency.resolve('EUR'),
      ).convertTo(Currency.resolve('USD'), 1.1).minorUnits,
    );
  });

  test('zero, negative and NaN rates are refused before any write', () async {
    final id = await addForeignNoRate();
    for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
        repo.setManualRate(id: id, fxRate: bad),
        throwsArgumentError,
        reason: 'rate $bad must never reach the database',
      );
    }
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.fxRate, isNull);
  });
}
