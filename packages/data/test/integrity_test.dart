import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

/// §7 — the passive boot health probe. Report-only: no dialogs, no throws.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late AppDatabase db;
  late LedgerRepository repo;

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  test('a healthy store answers ok with no problems', () async {
    final account = await repo.createAccount(
      name: 'Checking',
      currencyCode: 'USD',
    );
    await repo.addTransaction(
      accountId: account,
      date: DateTime(2026, 11, 2),
      amount: Money(500, Currency.resolve('USD')),
      source: TransactionSource.manual,
    );

    final report = await DbIntegrity.check(db);
    expect(report.ok, isTrue);
    expect(report.problems, isEmpty);
  });

  test('unenforced declared FKs and dangling rows are surfaced', () async {
    // drift's generated DDL contains no FOREIGN KEY clauses (its
    // .references() only types joins), so an orphan transaction row is
    // invisible to foreign_key_check by design. Create a raw table pair
    // that does declare a constraint — the "reopened through something
    // else" scenario §7's banner exists for.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
      'CREATE TABLE probe_parent (id INTEGER PRIMARY KEY)',
    );
    await db.customStatement(
      'CREATE TABLE probe_child (id INTEGER PRIMARY KEY, '
      'parent_id INTEGER REFERENCES probe_parent(id))',
    );
    await db.customStatement('INSERT INTO probe_child (parent_id) VALUES (42)');

    final report = await DbIntegrity.check(db);
    expect(report.ok, isFalse);
    expect(report.problems, contains('foreign key enforcement is disabled'));
    expect(
      report.problems.where((p) => p.startsWith('dangling reference:')),
      hasLength(1),
    );
    expect(
      report.problems.singleWhere((p) => p.startsWith('dangling')),
      contains('probe_child'),
    );

    await db.customStatement('PRAGMA foreign_keys = ON');
    final healed = await DbIntegrity.check(db);
    // The orphan is still there (enforcement on ⇒ no new message, but the
    // violation row remains — the probe must still see it).
    expect(healed.ok, isFalse);
    expect(
      healed.problems,
      isNot(contains('foreign key enforcement is disabled')),
    );
    expect(
      healed.problems.any((p) => p.startsWith('dangling reference:')),
      isTrue,
    );
  });

  test('violation report is capped, never unbounded', () async {
    await db.customStatement(
      'CREATE TABLE probe_parent (id INTEGER PRIMARY KEY)',
    );
    await db.customStatement(
      'CREATE TABLE probe_child (id INTEGER PRIMARY KEY, '
      'parent_id INTEGER REFERENCES probe_parent(id))',
    );
    for (var i = 0; i < 25; i++) {
      await db.customStatement(
        'INSERT INTO probe_child (parent_id) VALUES ($i)',
      );
    }

    final report = await DbIntegrity.check(db);
    expect(
      report.problems.where((p) => p.startsWith('dangling reference:')),
      hasLength(20),
    );
    expect(report.problems.any((p) => p.contains('showing first 20')), isTrue);
  });

  test('wal checkpoint is safe to call on a rollback-journal store', () async {
    await expectLater(DbIntegrity.walCheckpoint(db), completes);
  });
}
