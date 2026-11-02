import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

/// §3.5 (B6, #37): a goal movement is a transfer, not income or expense.
/// Every ledger-facing read — the month list (which also feeds the balance
/// strip) and the engine's range scan — must skip goal-tagged rows; only
/// [LedgerRepository.goalTransfers] may see them.
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

  Future<int> usdGoal({String name = 'Emergency'}) =>
      repo.addGoal(name: name, currencyCode: 'USD', targetMinor: 500000);

  Future<void> transfer(
    int goalId,
    int minor, {
    DateTime? date,
    bool isIncome = false,
  }) async => repo.addGoalTransfer(
    accountId: (await repo.defaultAccount()).id,
    goalId: goalId,
    date: date ?? DateTime(2026, 11, 2),
    amount: Money(minor, Currency.resolve('USD')),
    isIncome: isIncome,
  );

  test('watchMonth hides goal transfers — the strip sums these rows', () async {
    await repo.ensureDefaults();
    final food = (await repo.categories(income: false)).first;
    await repo.addEntry(
      date: DateTime(2026, 11, 2),
      amount: Money(500, Currency.resolve('USD')),
      isIncome: false,
      categoryId: food.id,
    );
    final goal = await usdGoal();
    await transfer(goal, 1000);
    await transfer(goal, 200, isIncome: true); // withdraw

    final rows = await repo.watchMonth('2026-11').first;
    expect(rows.map((r) => r.amountMinor), [500]);
  });

  test('transactionsInRange (the engine feed) skips goal rows', () async {
    await repo.ensureDefaults();
    await repo.addEntry(
      date: DateTime(2026, 11, 5),
      amount: Money(700, Currency.resolve('USD')),
      isIncome: false,
      categoryId: (await repo.categories(income: false)).first.id,
    );
    final goal = await usdGoal();
    await transfer(goal, 4000);

    final rows = await repo.transactionsInRange(
      epochDayOf(DateTime(2026, 11, 1)),
      epochDayOf(DateTime(2026, 11, 30)),
    );
    expect(rows, hasLength(1));
    expect(rows.single.amountMinor, 700);
    expect(rows.single.goalId, isNull);
  });

  test('goalTransfers: own goal only, newest first, direction kept', () async {
    final a = await usdGoal(name: 'Camera');
    final b = await usdGoal(name: 'Trip');
    await transfer(a, 1000, date: DateTime(2026, 11, 1));
    await transfer(a, 300, date: DateTime(2026, 11, 3), isIncome: true);
    await transfer(b, 9999, date: DateTime(2026, 11, 2));

    final rows = await repo.goalTransfers(a);
    expect(rows.map((t) => t.amountMinor), [300, 1000]); // newest first
    expect(rows.first.isIncome, isTrue); // withdraw
    expect(rows.last.isIncome, isFalse); // deposit
    expect(rows.every((t) => t.goalId == a), isTrue);
  });

  test('goal note round-trips through add/update (v5 column)', () async {
    final id = await repo.addGoal(
      name: 'Emergency',
      currencyCode: 'USD',
      targetMinor: 500000,
      note: 'three months of rent',
    );
    expect((await repo.goals()).single.note, 'three months of rent');

    await repo.updateGoal(id, note: const Value('six months'));
    expect((await repo.goals()).single.note, 'six months');

    // The editor's blank target = open-ended: Value(null) must CLEAR,
    // where a plain null means "leave alone".
    await repo.updateGoal(id, targetMinor: const Value<int?>(null));
    expect((await repo.goals()).single.targetMinor, isNull);
    await repo.updateGoal(id, note: const Value<String?>(null));
    expect((await repo.goals()).single.note, isNull);
  });
}
