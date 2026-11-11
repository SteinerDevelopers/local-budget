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

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  late AppDatabase db;
  late LedgerRepository repo;
  late int cash;

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    await repo.ensureDefaults();
    cash = (await repo.defaultAccount()).id;
  });
  tearDown(() => db.close());

  Future<void> spend(
    String merchant, {
    int year = 2026,
    int month = 11,
    int day = 5,
  }) => repo.addTransaction(
    accountId: cash,
    date: DateTime(year, month, day),
    amount: Money.tryParse('10.00', Currency.resolve('USD'))!,
    source: TransactionSource.manual,
    merchant: merchant,
  );

  group('merchantsLike (E4 §4)', () {
    test('ranks by usage count desc', () async {
      await spend('Food Co');
      await spend('Food Co');
      await spend('Food Co');
      await spend('Food Corner');
      expect(await repo.merchantsLike('Food'), ['Food Co', 'Food Corner']);
    });

    test('prefix match is case-insensitive', () async {
      await spend('Corner Store');
      expect(await repo.merchantsLike('corner'), ['Corner Store']);
      expect(await repo.merchantsLike('coRNer '), ['Corner Store']);
    });

    test('same count: most-recent use wins', () async {
      await spend('Tie-A', day: 9);
      await spend('Tie-B', day: 26);
      expect(await repo.merchantsLike('Tie-'), ['Tie-B', 'Tie-A']);
    });

    test('same count and recency: name asc keeps it deterministic', () async {
      await spend('Q Same B', day: 4);
      await spend('Q Same A', day: 4);
      expect(await repo.merchantsLike('Q Same'), ['Q Same A', 'Q Same B']);
    });

    test('unused merchants never surface (inner-join semantics)', () async {
      await repo.findOrCreateMerchant('Ghost LLC');
      expect(await repo.merchantsLike('Ghost'), isEmpty);
    });

    test('LIKE wildcards in the prefix are literal', () async {
      await spend('100% Mart');
      await spend('1000 Mart');
      await spend('A_B Store');
      await spend('AXB Store');
      expect(await repo.merchantsLike('100%'), ['100% Mart']);
      expect(await repo.merchantsLike('A_'), ['A_B Store']);
    });

    test('limit caps suggestions; E4 default is three', () async {
      for (final name in ['M1 a', 'M2 a', 'M3 a', 'M4 a']) {
        await spend(name);
      }
      expect(await repo.merchantsLike('M'), hasLength(3));
      expect(await repo.merchantsLike('M', limit: 4), hasLength(4));
    });

    test('merchant-free rows contribute nothing', () async {
      await repo.addTransaction(
        accountId: cash,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('5.00', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
      );
      expect(await repo.merchantsLike(''), isEmpty);
    });
  });
}
