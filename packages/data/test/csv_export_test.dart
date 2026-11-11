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

  group('csv codec', () {
    test('round-trips awkward fields (quotes, commas, newlines, unicode)', () {
      final rows = [
        ['date', 'description', 'amount'],
        ['2026-11-02', 'Café "Midday", Main St', '-12.34'],
        ['2026-11-01', 'multi\nline\nnote', '0'],
        ['2026-10-31', 'trailing space  ', '1,234.56'],
        ['2026-10-30', 'ümlaut — em-dash → arrow', '9.99'],
      ];
      expect(decodeCsv(encodeCsv(rows)), rows);
    });

    test('encode quotes only when required, CRLF line endings', () {
      final out = encodeCsv([
        ['plain', 'has,comma', 'has"quote'],
      ]);
      expect(out, 'plain,"has,comma","has""quote"\r\n');
    });

    test('decode tolerates CRLF, bare LF, quoted newlines, blank lines', () {
      final text = 'a,b\r\nc,d\n\r\n"e\nf",g\r\n';
      expect(decodeCsv(text), [
        ['a', 'b'],
        ['c', 'd'],
        ['e\nf', 'g'],
      ]);
    });

    test('sniffDelimiter picks ; and tab outside quotes', () {
      expect(sniffDelimiter('date;amount;"desc;with;commas"'), ';');
      expect(sniffDelimiter('date\tamount\tdesc'), '\t');
      expect(sniffDelimiter('date,amount,desc'), ',');
      expect(sniffDelimiter('single'), ',');
    });
  });

  group('csv export', () {
    late AppDatabase db;
    late LedgerRepository repo;
    late CsvExport export;

    setUp(() {
      db = AppDatabase.inMemory();
      repo = LedgerRepository(db);
      export = CsvExport(db);
    });
    tearDown(() => db.close());

    Future<int> usd() => repo.createAccount(name: 'Cash', currencyCode: 'USD');
    Future<int> eur() =>
        repo.createAccount(name: 'Travel', currencyCode: 'EUR');

    test('header + signed amounts + sort + joins', () async {
      final a = await usd();
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('12.34', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        merchant: 'Corner Store',
        note: 'milk & eggs',
      );
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 1),
        amount: Money.tryParse('2000', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        isIncome: true,
        note: 'salary',
      );
      final csv = await export.build();
      final rows = decodeCsv(csv);
      expect(rows.first, CsvExport.header);
      // Sorted date→id: income (Nov 1) before expense (Nov 2).
      expect(rows[1], [
        '2026-11-01',
        'salary', // description falls back to note
        '',
        'salary',
        '2000.00', // income positive; fixed decimals for 2-minor currencies
        'USD',
        'Cash',
      ]);
      expect(rows[2][0], '2026-11-02');
      expect(rows[2][1], 'Corner Store'); // merchant wins over note
      expect(rows[2][4], '-12.34');
      expect(rows[2][6], 'Cash');
    });

    test('income keeps decimals; zero expense has no sign', () async {
      final a = await usd();
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('0.50', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        isIncome: true,
      );
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 2),
        amount: Money(0, Currency.resolve('USD')),
        source: TransactionSource.manual,
      );
      final rows = decodeCsv(await export.build());
      expect(rows[1][4], '0.50');
      expect(rows[2][4], '0');
    });

    test('JPY (0 decimals) and BHD (3 decimals) format by exponent', () async {
      final jpy = await repo.createAccount(name: 'Tokyo', currencyCode: 'JPY');
      await repo.addTransaction(
        accountId: jpy,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('1485', Currency.resolve('JPY'))!,
        source: TransactionSource.manual,
      );
      final bhd = await repo.createAccount(name: 'Manama', currencyCode: 'BHD');
      await repo.addTransaction(
        accountId: bhd,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('1.234', Currency.resolve('BHD'))!,
        source: TransactionSource.manual,
      );
      final rows = decodeCsv(await export.build());
      expect(rows[1][4], '-1485');
      expect(rows[2][4], '-1.234');
    });

    test('goal transfers are excluded; account filter works', () async {
      final a = await usd();
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('5', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        merchant: 'Snack',
      );
      final goal = await repo.addGoal(
        name: 'Camera',
        currencyCode: 'USD',
        targetMinor: 100000,
      );
      await repo.addGoalTransfer(
        goalId: goal,
        accountId: a,
        amount: Money.tryParse('10', Currency.resolve('USD'))!,
        date: DateTime(2026, 11, 2),
      );
      final b = await eur();
      await repo.addTransaction(
        accountId: b,
        date: DateTime(2026, 11, 2),
        amount: Money.tryParse('9.99', Currency.resolve('EUR'))!,
        source: TransactionSource.manual,
      );

      final all = decodeCsv(await export.build());
      expect(all.length, 3); // header + snack + EUR expense, no transfer
      final onlyUsd = decodeCsv(await export.build(accountId: a));
      expect(onlyUsd.length, 2);
      expect(onlyUsd[1][6], 'Cash');
    });

    test('fileName is budget-export-YYYY-MM-DD.csv', () {
      expect(
        CsvExport.fileName(DateTime(2026, 3, 7)),
        'budget-export-2026-03-07.csv',
      );
    });
  });
}
