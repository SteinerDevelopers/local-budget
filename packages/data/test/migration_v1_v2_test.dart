import 'dart:ffi';
import 'dart:io';

import 'package:data/data.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:test/test.dart';

/// Beta-prep matrix: the OLDEST shipped shapes (schema v1 = first dev
/// release, v2 = icon-key release #18) must also upgrade cleanly to head.
/// v3..v5 are pinned by migration_v4/v5/v6_test; this closes the two
/// bottom rungs beta testers can actually arrive on.
///
/// v1 vs the v3 DDL in migration_v4_test: no `icon` column on categories
/// (v2 added it) and no `tx_date` index (v3 added it). Everything else is
/// identical — same constraints, same index names.
List<String> legacyDdl(int version) => [
  '''
  CREATE TABLE accounts (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    currency_code TEXT NOT NULL CHECK (length(currency_code) BETWEEN 3 AND 3),
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at_ms INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE categories (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    parent_id INTEGER,
    sort_order INTEGER NOT NULL DEFAULT 0,
    color_hint INTEGER,
    ${version >= 2 ? 'icon TEXT,' : ''}
    is_income INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE TABLE merchants (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)',
  '''
  CREATE TABLE transactions (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL REFERENCES accounts (id),
    category_id INTEGER REFERENCES categories (id),
    merchant_id INTEGER REFERENCES merchants (id),
    date_days INTEGER NOT NULL,
    amount_minor INTEGER NOT NULL,
    currency_code TEXT NOT NULL CHECK (length(currency_code) BETWEEN 3 AND 3),
    base_amount_minor INTEGER,
    fx_rate REAL,
    note TEXT,
    image_ref TEXT,
    source TEXT NOT NULL,
    is_income INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE budgets (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER REFERENCES categories (id),
    year_month TEXT NOT NULL CHECK (length(year_month) BETWEEN 7 AND 7),
    limit_minor INTEGER NOT NULL,
    currency_code TEXT NOT NULL CHECK (length(currency_code) BETWEEN 3 AND 3)
  )
  ''',
  'CREATE UNIQUE INDEX budget_month ON budgets (category_id, year_month)',
  'CREATE TABLE line_items (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER NOT NULL REFERENCES transactions (id), position INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL, quantity REAL, unit_price_minor INTEGER, currency_code TEXT NOT NULL CHECK (length(currency_code) BETWEEN 3 AND 3))',
  'CREATE TABLE settings ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE INDEX tx_account_date ON transactions (account_id, date_days)',
  if (version >= 3) 'CREATE INDEX tx_date ON transactions (date_days)',
  'PRAGMA user_version = $version',
];

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  for (final from in [1, 2]) {
    group('schema v$from upgrades to head', () {
      late Directory tmp;
      late String path;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('budget_mig_v$from');
        path = '${tmp.path}/ledger.sqlite';
        final db = raw_sqlite3.sqlite3.open(path);
        for (final ddl in legacyDdl(from)) {
          db.execute(ddl);
        }
        db.execute(
          "INSERT INTO accounts (name, currency_code, created_at_ms) "
          "VALUES ('Cash', 'USD', 1)",
        );
        db.execute("INSERT INTO categories (name) VALUES ('Food')");
        db.execute(
          "INSERT INTO budgets (category_id, year_month, limit_minor, "
          "currency_code) VALUES (1, '2026-11', 25000, 'USD')",
        );
        db.execute(
          "INSERT INTO transactions (account_id, category_id, date_days, "
          "amount_minor, currency_code, source) "
          "VALUES (1, 1, 20760, 1234, 'USD', 'manual')",
        );
        db.dispose();
      });
      tearDown(() => tmp.deleteSync(recursive: true));

      test('rows survive, v2..v6 steps land, integrity holds', () async {
        final db = AppDatabase.openFile(path);
        final repo = LedgerRepository(db);
        addTearDown(db.close);

        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          6,
        );

        // Data survived every rung.
        final food = await repo.budgetFor(categoryId: 1, yearMonth: '2026-11');
        expect(food?.limitMinor, 25000);
        expect(food?.periodType, 'monthly');
        final txs = await repo.transactionsForMonth('2026-11');
        expect(txs.single.amountMinor, 1234);

        // v2 rung: icon column added.
        final cols = await db
            .customSelect("PRAGMA table_info('categories')")
            .get();
        expect(cols.map((r) => r.data['name']), contains('icon'));

        // v3/v4/v6 rungs: index set matches what fresh installs get.
        Future<Set<String>> indexesOf(String table) async {
          final rows = await db.customSelect('PRAGMA index_list($table)').get();
          return rows.map((r) => r.data['name'] as String).toSet();
        }

        expect(
          await indexesOf('transactions'),
          containsAll(['tx_date', 'tx_account_external']),
        );
        final budgetIdx = await indexesOf('budgets');
        expect(budgetIdx, contains('budget_month_period'));
        expect(budgetIdx, isNot(contains('budget_month')));

        // v4 rung: new tables exist.
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name IN ('goals','recurring_rules')",
            )
            .get();
        expect(tables, hasLength(2));

        expect(
          (await db.customSelect('PRAGMA integrity_check').getSingle())
              .data['integrity_check'],
          'ok',
        );
      });

      test('second open is a clean no-op (re-runnable migrations)', () async {
        final first = AppDatabase.openFile(path);
        await first.customSelect('PRAGMA user_version').get();
        await first.close();
        final second = AppDatabase.openFile(path);
        addTearDown(second.close);
        expect(
          (await second.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          6,
        );
        final cols = await second
            .customSelect("PRAGMA table_info('categories')")
            .get();
        // icon exactly once — the from<2 step did not double-add.
        expect(cols.where((r) => r.data['name'] == 'icon'), hasLength(1));
      });
    });
  }
}
