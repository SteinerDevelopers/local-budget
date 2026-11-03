import 'dart:ffi';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:test/test.dart';

/// DDL as drift generated it for schema v3 (snake_case columns, same
/// constraints) — the exact shape a shipped dev install has on disk.
const _legacyV3Ddl = [
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
    icon TEXT,
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
  'CREATE INDEX tx_date ON transactions (date_days)',
  'PRAGMA user_version = 3',
];

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory tmp;
  late String path;

  /// Builds a v3 database with pre-upgrade rows, exactly as an installed
  /// dev build would have it on disk.
  void createLegacyDb() {
    final db = raw_sqlite3.sqlite3.open(path);
    for (final ddl in _legacyV3Ddl) {
      db.execute(ddl);
    }
    db.execute(
      "INSERT INTO accounts (name, currency_code, created_at_ms) "
      "VALUES ('Cash', 'USD', 1)",
    );
    db.execute("INSERT INTO categories (name) VALUES ('Food')");
    db.execute(
      "INSERT INTO budgets (category_id, year_month, limit_minor, currency_code) "
      "VALUES (1, '2026-11', 25000, 'USD')",
    );
    db.execute(
      "INSERT INTO budgets (category_id, year_month, limit_minor, currency_code) "
      "VALUES (NULL, '2026-11', 400000, 'USD')",
    );
    db.execute(
      "INSERT INTO transactions (account_id, category_id, date_days, amount_minor, "
      "currency_code, source) VALUES (1, 1, 20760, 1234, 'USD', 'manual')",
    ); // date_days 20760 = 2026-11-03
    db.dispose();
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('budget_mig_v4');
    path = '${tmp.path}/ledger.sqlite';
    createLegacyDb();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('v3 rows survive the upgrade with monthly defaults', () async {
    final db = AppDatabase.openFile(path);
    final repo = LedgerRepository(db);
    addTearDown(db.close);

    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data['user_version'],
      // Upgrades run to the live schemaVersion; v5 (goals.note) and v6
      // (transactions.externalId) ride along because the v4 step's
      // createTable already carries the columns.
      6,
    );

    final food = await repo.budgetFor(categoryId: 1, yearMonth: '2026-11');
    expect(food, isNotNull);
    expect(food!.limitMinor, 25000);
    expect(food.periodType, 'monthly');
    expect(food.rolloverCapMinor, isNull);

    final overall = await repo.budgetFor(yearMonth: '2026-11');
    expect(overall?.categoryId, isNull);
    expect(overall?.limitMinor, 400000);

    final txs = await repo.transactionsForMonth('2026-11');
    expect(txs, hasLength(1));
    expect(txs.single.amountMinor, 1234);
    expect(txs.single.goalId, isNull);

    // The old month-unique index is gone; period-unique replaced it.
    final indexes = await db.customSelect('PRAGMA index_list(budgets)').get();
    final names = indexes.map((r) => r.data['name']).toSet();
    expect(names, isNot(contains('budget_month')));
    expect(names, contains('budget_month_period'));
  });

  test(
    'same category + month may hold one budget per periodType, not two',
    () async {
      final db = AppDatabase.openFile(path);
      final repo = LedgerRepository(db);
      addTearDown(db.close);

      // Weekly row beside the migrated monthly row: legal post-upgrade.
      await repo.setBudget(
        categoryId: 1,
        yearMonth: '2026-11',
        limitMinor: 6000,
        currencyCode: 'USD',
        periodType: 'weekly',
      );
      // category-monthly (migrated) + overall-monthly (migrated) + weekly.
      expect(await repo.budgetsIn('2026-11'), hasLength(3));

      // Same (category, anchor, periodType) via raw insert: rejected.
      expect(
        () => db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: const Value(1),
                yearMonth: '2026-11',
                limitMinor: 9999,
                currencyCode: 'USD',
              ),
            ),
        throwsA(isA<raw_sqlite3.SqliteException>()),
      );
    },
  );

  test('rules, goals, goal transfers and settings round-trip', () async {
    final db = AppDatabase.openFile(path);
    final repo = LedgerRepository(db);
    addTearDown(db.close);

    final ruleId = await repo.addRule(
      name: 'Rent',
      amountMinor: 90000,
      currencyCode: 'USD',
      frequency: 'monthly',
      start: DateTime.utc(2026, 1, 1),
      nextDue: DateTime.utc(2026, 11, 1),
      categoryId: 1,
      dayOfMonth: 1,
    );
    expect(ruleId, greaterThan(0));
    final rules = await repo.rules();
    expect(rules.single.name, 'Rent');
    expect(rules.single.notify, isTrue);
    expect(rules.single.archived, isFalse);

    await repo.updateRuleDue(id: ruleId, nextDue: DateTime.utc(2026, 12, 1));
    expect(
      (await repo.rules()).single.nextDueMs,
      DateTime.utc(2026, 12, 1).millisecondsSinceEpoch,
    );
    await repo.archiveRule(ruleId);
    expect(await repo.rules(), isEmpty);
    expect(await repo.rules(includeArchived: true), hasLength(1));

    final goalId = await repo.addGoal(
      name: 'Tires',
      currencyCode: 'USD',
      targetMinor: 40000,
    );
    final account = await repo.defaultAccount();
    final txId = await repo.addGoalTransfer(
      accountId: account.id,
      goalId: goalId,
      date: DateTime.utc(2026, 11, 3),
      amount: Money(5000, Currency.resolve('USD')),
    );
    final tx = (await repo.transactionsForMonth(
      '2026-11',
    )).firstWhere((t) => t.id == txId);
    expect(tx.goalId, goalId);
    expect(tx.isIncome, isFalse);

    expect(await repo.budgetRollover(), isFalse); // absent = off
    await repo.setBudgetRollover(true);
    expect(await repo.budgetRollover(), isTrue);
    expect(await repo.billsLastMaterializeMs(), isNull);
    await repo.setBillsLastMaterializeMs(123);
    expect(await repo.billsLastMaterializeMs(), 123);
  });

  test('fresh installs get the v4 shape directly', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final indexes = await db.customSelect('PRAGMA index_list(budgets)').get();
    final names = indexes.map((r) => r.data['name']).toSet();
    expect(names, contains('budget_month_period'));
    expect(names, isNot(contains('budget_month')));
  });
}
