import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

void main() {
  // Runtimes ship libsqlite3.so.0 (SONAME); the bare libsqlite3.so symlink
  // only exists with the -dev package, which CI images don't carry.
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

  Future<int> cashAccount() =>
      repo.createAccount(name: 'Cash', currencyCode: 'USD');

  group('month math', () {
    test('monthRange covers the calendar month exactly', () {
      final r = monthRange('2026-02'); // non-leap
      expect(dateFromEpochDay(r.fromDays), DateTime.utc(2026, 2, 1));
      expect(dateFromEpochDay(r.toDays), DateTime.utc(2026, 2, 28));
      final leap = monthRange('2028-02');
      expect(dateFromEpochDay(leap.toDays), DateTime.utc(2028, 2, 29));
      final dec = monthRange('2026-12'); // month+1 year rollover
      expect(dateFromEpochDay(dec.toDays), DateTime.utc(2026, 12, 31));
    });

    test('monthRange rejects garbage', () {
      for (final bad in ['2026-13', '26-11', '2026-1', 'x', '']) {
        expect(() => monthRange(bad), throwsArgumentError, reason: bad);
      }
    });

    test('yearMonthOf zero-pads', () {
      expect(yearMonthOf(DateTime(2026, 3, 17)), '2026-03');
    });
  });

  group('ledger round-trips', () {
    test(
      'transaction stores money as minor units + code + source wire name',
      () async {
        final id = await repo.addTransaction(
          accountId: await cashAccount(),
          date: DateTime(2026, 11, 2),
          amount: Money.tryParse('12.34', Currency.resolve('USD'))!,
          source: TransactionSource.cameraScan,
          merchant: 'Corner Store',
        );
        expect(id, greaterThan(0));
        final tx = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(tx.amountMinor, 1234);
        expect(tx.currencyCode, 'USD');
        expect(tx.source, TransactionSource.cameraScan);
        expect(tx.dateDays, epochDayOf(DateTime(2026, 11, 2)));
        // merchant de-duplicated by name
        final merchant = await (db.select(db.merchants)).getSingle();
        expect(merchant.name, 'Corner Store');
        expect(tx.merchantId, merchant.id);
      },
    );

    test('unknown source wire name is rejected on read', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: await cashAccount(),
              dateDays: epochDayOf(DateTime(2026, 11, 1)),
              amountMinor: 100,
              currencyCode: 'USD',
              source: TransactionSource.manual,
            ),
          );
      final raw = await db
          .customSelect('select source from transactions')
          .getSingle();
      expect(raw.read<String>('source'), 'manual');
      expect(
        () => TransactionSource.fromWire('carrier_pigeon'),
        throwsArgumentError,
      );
    });

    test('fx snapshot filled only when currencies differ', () async {
      final acc = await cashAccount();
      await repo.setBaseCurrency('USD');
      final jpyTx = await repo.addTransaction(
        accountId: acc,
        date: DateTime(2026, 11, 3),
        amount: Money(1000, Currency.resolve('USD')),
        source: TransactionSource.manual,
        baseCurrencyCode: 'JPY',
        fxRate: 148.5,
      );
      final usdTx = await repo.addTransaction(
        accountId: acc,
        date: DateTime(2026, 11, 3),
        amount: Money(500, Currency.resolve('USD')),
        source: TransactionSource.manual,
        baseCurrencyCode: 'USD',
        fxRate: 148.5, // same currency: must NOT create a snapshot
      );
      final j = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(jpyTx))).getSingle();
      expect(
        j.baseAmountMinor,
        1485,
      ); // $10.00 x 148.5 = ¥1,485 (JPY: 0 minor digits)
      expect(j.fxRate, 148.5);
      final u = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(usdTx))).getSingle();
      expect(u.baseAmountMinor, isNull);
      expect(u.fxRate, isNull);
    });

    test('monthSpendMinor sums original currency, refunds subtract', () async {
      final acc = await cashAccount();
      Future<void> tx(String raw, {int? categoryId}) => repo.addTransaction(
        accountId: acc,
        date: DateTime(2026, 11, 10),
        amount: Money.tryParse(raw, Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        categoryId: categoryId,
      );
      await tx('12.50');
      await tx('7.25');
      await tx('-2.00'); // refund
      await repo.addTransaction(
        accountId: acc,
        date: DateTime(2026, 12, 1),
        amount: Money.tryParse('999.00', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
      );
      expect(
        await repo.monthSpendMinor(yearMonth: '2026-11', currencyCode: 'USD'),
        1775,
      );
      expect(
        await repo.monthSpendMinor(yearMonth: '2026-12', currencyCode: 'USD'),
        99900,
      );
    });
  });

  group('budgets', () {
    test(
      'setBudget replaces overall and category budgets independently',
      () async {
        await repo.setBudget(
          yearMonth: '2026-11',
          limitMinor: 200000,
          currencyCode: 'USD',
        );
        await repo.setBudget(
          categoryId: 7,
          yearMonth: '2026-11',
          limitMinor: 30000,
          currencyCode: 'USD',
        );
        await repo.setBudget(
          yearMonth: '2026-11',
          limitMinor: 250000,
          currencyCode: 'USD',
        );
        final overall = await repo.budgetFor(yearMonth: '2026-11');
        expect(overall?.limitMinor, 250000);
        expect(overall?.categoryId, isNull);
        final groceries = await repo.budgetFor(
          categoryId: 7,
          yearMonth: '2026-11',
        );
        expect(groceries?.limitMinor, 30000);
        expect(
          await repo.budgetFor(categoryId: 8, yearMonth: '2026-11'),
          isNull,
        );
      },
    );
  });

  group('reserved + settings', () {
    test(
      'line_items table exists and accepts rows (v2 ready, decision 2)',
      () async {
        final txId = await repo.addTransaction(
          accountId: await cashAccount(),
          date: DateTime(2026, 11, 4),
          amount: Money(450, Currency.resolve('USD')),
          source: TransactionSource.cameraScan,
        );
        await db
            .into(db.lineItems)
            .insert(
              LineItemsCompanion.insert(
                transactionId: txId,
                name: 'Latte',
                unitPriceMinor: const Value(450),
                currencyCode: 'USD',
              ),
            );
        final row = (await db.select(db.lineItems).getSingle());
        expect(row.name, 'Latte');
        expect(row.transactionId, txId);
      },
    );

    test('base currency setting round-trips, unknown codes rejected', () async {
      expect(await repo.baseCurrency(), isNull);
      await repo.setBaseCurrency('EUR');
      expect(await repo.baseCurrency(), 'EUR');
      await expectLater(repo.setBaseCurrency('XYZ'), throwsArgumentError);
    });
  });
}
