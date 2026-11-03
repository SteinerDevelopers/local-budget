// E5 §6 — the No-rate row and its detail sheet: an amber whisper on the
// row, one honest manual-rate field in the sheet, and delete still flows
// through the ledger's Undo path (the sheet never deletes by itself).
//
// Same drift rules as manage_test.dart: db.close() INSIDE the test body.
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late AppDatabase db;
  late LedgerRepository repo;

  Future<int> seed({
    required String code,
    required int minor,
    double? fxRate,
    String? baseCode,
  }) async {
    await repo.ensureDefaults();
    final account = await repo.defaultAccount();
    final cats = await repo.categories();
    return repo.addTransaction(
      accountId: account.id,
      date: DateTime.now(),
      amount: Money(minor, Currency.resolve(code)),
      source: TransactionSource.manual,
      categoryId: cats.first.id,
      baseCurrencyCode: baseCode,
      fxRate: fxRate,
    );
  }

  setUp(() {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpLedger(WidgetTester tester) async {
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String rowText) async {
    await tester.tap(find.text(rowText).first);
    await tester.pumpAndSettle();
  }

  testWidgets('foreign row saved without a rate whispers No rate', (
    tester,
  ) async {
    await seed(code: 'EUR', minor: 1000);
    await pumpLedger(tester);
    expect(find.byKey(const Key('no-rate')), findsOneWidget);
    // The row is real data — it renders its own currency, untouched.
    expect(find.textContaining('10.00'), findsWidgets);
    await db.close();
  });

  testWidgets('base-currency and rated rows show no amber whisper', (
    tester,
  ) async {
    await seed(code: 'USD', minor: 500);
    await seed(code: 'EUR', minor: 1000, baseCode: 'USD', fxRate: 1.08);
    await pumpLedger(tester);
    expect(find.byKey(const Key('no-rate')), findsNothing);
    await db.close();
  });

  testWidgets('tapping a row opens the detail sheet with the snapshot line', (
    tester,
  ) async {
    await seed(code: 'EUR', minor: 1000, baseCode: 'USD', fxRate: 1.0834);
    await pumpLedger(tester);
    await openDetail(tester, 'Food');
    expect(find.text('Food'), findsWidgets); // category meta row
    // The rate, spelled out: what it became and at what rate.
    expect(find.byKey(const Key('detail-rate-line')), findsOneWidget);
    expect(find.textContaining('1 EUR = 1.0834 USD'), findsOneWidget);
    // Read-only: no rate field on a rated row, only the delete affordance.
    expect(find.byKey(const Key('manual-rate-field')), findsNothing);
    await db.close();
  });

  testWidgets('No-rate sheet takes one manual rate and restamps the row', (
    tester,
  ) async {
    await seed(code: 'EUR', minor: 1000);
    await pumpLedger(tester);
    await openDetail(tester, 'Food');
    expect(find.byKey(const Key('manual-rate-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('manual-rate-field')),
      '0,9', // a comma is as human as a dot
    );
    await tester.tap(find.byKey(const Key('manual-rate-save')));
    await tester.pumpAndSettle();

    expect(find.text('Rate added'), findsOneWidget);
    expect(find.byKey(const Key('no-rate')), findsNothing); // stream refreshed

    // Reopen: the snapshot is real now, at the audited €10 → $9.
    await tester.tap(find.text('Food').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-rate-line')), findsOneWidget);
    expect(find.textContaining('1 EUR = 0.9 USD'), findsOneWidget);
    await db.close();
  });

  testWidgets('a nonsense rate is refused before any write', (tester) async {
    final id = await seed(code: 'EUR', minor: 1000);
    await pumpLedger(tester);
    await openDetail(tester, 'Food');
    await tester.enterText(find.byKey(const Key('manual-rate-field')), '-3');
    await tester.tap(find.byKey(const Key('manual-rate-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive number'), findsOneWidget);
    expect(find.byKey(const Key('manual-rate-field')), findsOneWidget);
    // Sheet still open, row still rate-less.
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.fxRate, isNull);
    await db.close();
  });

  testWidgets('Delete in the sheet is the ledger’s delete — Undo and all', (
    tester,
  ) async {
    await seed(code: 'USD', minor: 500);
    await pumpLedger(tester);
    await openDetail(tester, 'Food');
    await tester.tap(find.byKey(const Key('detail-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget); // §2.1 safety net intact
    await db.close();
  });
}
