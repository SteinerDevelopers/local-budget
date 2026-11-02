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

  setUp(() {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  group('ensureDefaults (first launch)', () {
    test('seeds one Cash account and the default category lists', () async {
      await repo.ensureDefaults();
      final account = await repo.defaultAccount();
      expect(account.name, 'Cash');
      expect(account.currencyCode, 'USD');

      final expense = await repo.categories(income: false);
      final income = await repo.categories(income: true);
      expect(
        expense.map((c) => c.name),
        LedgerE1.defaultExpenseCategories.keys,
      );
      expect(income.map((c) => c.name), LedgerE1.defaultIncomeCategories.keys);
      // #18: each seed row carries its icon-registry key (§2.4).
      expect(
        expense.map((c) => c.icon),
        LedgerE1.defaultExpenseCategories.values,
      );
      expect(expense.map((c) => c.sortOrder), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('is idempotent — a second call seeds nothing twice', () async {
      await repo.ensureDefaults();
      await repo.ensureDefaults();
      expect(await repo.categories(), hasLength(9));
      expect(await repo.accounts(), hasLength(1));
    });
  });

  group('addEntry (§2.2 → row)', () {
    test('stores unsigned amount + explicit income flag', () async {
      await repo.ensureDefaults();
      final cat = (await repo.categories(income: true)).first;
      final id = await repo.addEntry(
        date: DateTime(2026, 11, 2),
        amount: Money(1240, Currency.resolve('USD')),
        isIncome: true,
        categoryId: cat.id,
        note: 'milk',
      );
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.amountMinor, 1240);
      expect(row.isIncome, isTrue);
      expect(row.source, TransactionSource.manual);
      expect(row.note, 'milk');
    });

    test(
      'refuses signed amounts (§3 sign rule lives in the display layer)',
      () async {
        await repo.ensureDefaults();
        final cat = (await repo.categories()).first;
        expect(
          () => repo.addEntry(
            date: DateTime(2026, 11, 2),
            amount: Money(-5, Currency.resolve('USD')),
            isIncome: false,
            categoryId: cat.id,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('watchMonth (§2.1 list)', () {
    test(
      'newest day first, category name joined, other months excluded',
      () async {
        await repo.ensureDefaults();
        final food = (await repo.categories(income: false)).first;
        await repo.addEntry(
          date: DateTime(2026, 11, 2),
          amount: Money(500, Currency.resolve('USD')),
          isIncome: false,
          categoryId: food.id,
        );
        await repo.addEntry(
          date: DateTime(2026, 11, 1),
          amount: Money(700, Currency.resolve('USD')),
          isIncome: false,
          categoryId: food.id,
        );
        await repo.addEntry(
          date: DateTime(2026, 10, 31),
          amount: Money(999, Currency.resolve('USD')),
          isIncome: false,
          categoryId: food.id,
        );

        final rows = await repo.watchMonth('2026-11').first;
        expect(rows, hasLength(2));
        expect(rows.first.day, DateTime(2026, 11, 2));
        expect(rows.first.categoryName, food.name);
        expect(rows.first.amountMinor, 500);
      },
    );

    test('emits again when a row is added', () async {
      await repo.ensureDefaults();
      final cat = (await repo.categories()).first;
      // Subscribe first, then mutate — drift replays the current result on
      // listen, so the ledger must show [0, 1] without racing the insert.
      final values = <int>[];
      final sub = repo
          .watchMonth('2026-11')
          .map((r) => r.length)
          .listen(values.add);
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      await waitFor(() => values.isNotEmpty);
      expect(values, [0]);
      await repo.addEntry(
        date: DateTime(2026, 11, 2),
        amount: Money(10, Currency.resolve('USD')),
        isIncome: false,
        categoryId: cat.id,
      );
      await waitFor(() => values.length >= 2);
      await sub.cancel();
      expect(values.last, 1);
    });
  });

  group('deleteEntry + restoreEntry (undo, zero dialogs)', () {
    test('delete returns the row so undo can re-insert it exactly', () async {
      await repo.ensureDefaults();
      final cat = (await repo.categories()).first;
      final id = await repo.addEntry(
        date: DateTime(2026, 11, 2),
        amount: Money(640, Currency.resolve('USD')),
        isIncome: false,
        categoryId: cat.id,
        note: 'stationery',
      );
      final removed = await repo.deleteEntry(id);
      expect(removed, isNotNull);
      expect(
        await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull(),
        isNull,
      );

      await repo.restoreEntry(removed!);
      final rows = await repo.watchMonth('2026-11').first;
      expect(rows, hasLength(1));
      expect(rows.single.note, 'stationery');
      expect(rows.single.amountMinor, 640);
      // §2.1: "the undo reuses the exact row id".
      expect(rows.single.id, id);
    });
  });

  group('Manage screen backing (#18, spec §2.4)', () {
    test(
      'updateCategory renames and re-icons without touching order',
      () async {
        await repo.ensureDefaults();
        final food = (await repo.categories(income: false)).first;
        expect(food.name, 'Food');

        await repo.updateCategory(food.id, name: 'Coffee', icon: 'local_cafe');

        final coffee = (await repo.categories(income: false)).first;
        expect(coffee.name, 'Coffee');
        expect(coffee.icon, 'local_cafe');
        expect(coffee.sortOrder, food.sortOrder);
        // Partial update: omitting a field leaves it untouched.
        await repo.updateCategory(food.id, name: 'Food');
        expect((await repo.categories(income: false)).first.icon, 'local_cafe');
      },
    );

    test('reorderCategories persists the dragged section order', () async {
      await repo.ensureDefaults();
      final before = await repo.categories(income: false);
      final ids = before.map((c) => c.id).toList();
      final moved = [ids[1], ids[0], ...ids.skip(2)];

      await repo.reorderCategories(income: false, orderedIds: moved);

      final after = await repo.categories(income: false);
      expect(after.map((c) => c.id), moved);
      expect(after.map((c) => c.sortOrder), [0, 1, 2, 3, 4, 5, 6]);
      // The other section is untouched (seeding numbers a single shared
      // counter; sections render filtered, so absolute values don't matter).
      final income = await repo.categories(income: true);
      expect(income.map((c) => c.sortOrder), [7, 8]);
    });

    test('watchCategories re-emits after rename, add and reorder', () async {
      await repo.ensureDefaults();
      final cats = await repo.categories(income: false);
      final events = <List<String>>[];
      final sub = repo.watchCategories().listen(
        (rows) => events.add(
          rows.where((c) => !c.isIncome).map((c) => c.name).toList(),
        ),
      );
      await pumpEventQueue();

      final id = await repo.addCategory('Pets', icon: 'pets', sortOrder: 7);
      await repo.updateCategory(id, name: 'Animals');
      await repo.reorderCategories(
        income: false,
        orderedIds: [id, ...cats.map((c) => c.id)],
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(events.last.first, 'Animals'); // drag put it on top
      expect(events.last, hasLength(8));
    });

    test(
      'setBaseCurrency validates and round-trips through baseCurrency()',
      () async {
        expect(
          await repo.baseCurrency(),
          isNull,
        ); // unset until the app sets it
        await repo.setBaseCurrency('EUR');
        expect(await repo.baseCurrency(), 'EUR');
        await repo.setBaseCurrency('JPY'); // upsert, not insert-conflict crash
        expect(await repo.baseCurrency(), 'JPY');
        expect(() => repo.setBaseCurrency('XX'), throwsA(isA<ArgumentError>()));
      },
    );
  });
}
