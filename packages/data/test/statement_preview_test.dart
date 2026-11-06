import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');

  group('previewStatement — document rows into the E5 preview (E11 §3)', () {
    late AppDatabase db;
    late LedgerRepository repo;
    late CsvImport imp;
    late int accountId;

    setUp(() async {
      db = AppDatabase.inMemory();
      repo = LedgerRepository(db);
      await repo.ensureDefaults(); // the seed categories exist here
      imp = CsvImport(db);
      accountId = await repo.createAccount(
        name: 'Checking',
        currencyCode: 'USD',
      );
    });
    tearDown(() => db.close());

    final rows = [
      StatementRow(
        date: DateTime(2026, 10, 30),
        minor: 1234,
        isIncome: false,
        description: 'Corner Store',
      ),
      StatementRow(
        date: DateTime(2026, 11, 1),
        minor: 250000,
        isIncome: true,
        description: 'Salary Corp',
      ),
      StatementRow(
        date: DateTime(2026, 11, 2),
        minor: 350,
        isIncome: false,
        description: 'Cafe Late',
      ),
    ];

    Future<CsvPreview> preview() =>
        imp.previewStatement(accountId: accountId, currency: usd, rows: rows);

    test('maps 1:1 to CsvPreviewRow, nothing invented', () async {
      final p = await preview();
      expect(p.rows.map((r) => r.rowIndex), [0, 1, 2]);
      expect(p.rows.map((r) => r.date), rows.map((r) => r.date));
      expect(p.rows.map((r) => r.minor), [1234, 250000, 350]);
      expect(p.rows.map((r) => r.isIncome), [false, true, false]);
      expect(p.rows.map((r) => r.description), [
        'Corner Store',
        'Salary Corp',
        'Cafe Late',
      ]);
      expect(p.rows.every((r) => r.externalId == null), isTrue);
      expect(p.rows.every((r) => !r.duplicate), isTrue);
      expect(p.errors, isEmpty);
      expect(p.currency, usd);
      expect(p.newCount, 3);
    });

    test('duplicate flag is the E5 date|amount|direction tuple', () async {
      await repo.addTransaction(
        accountId: accountId,
        date: DateTime(2026, 10, 30),
        amount: Money(1234, usd),
        source: TransactionSource.manual,
        isIncome: false,
      );
      final p = await preview();
      expect(p.rows[0].duplicate, isTrue);
      expect(p.rows[1].duplicate, isFalse);
      expect(p.duplicateCount, 1);
    });

    test('direction distinguishes otherwise equal tuples', () async {
      await repo.addTransaction(
        accountId: accountId,
        date: DateTime(2026, 10, 30),
        amount: Money(1234, usd),
        source: TransactionSource.manual,
        isIncome: true, // same day+amount, income side
      );
      final p = await preview();
      expect(p.rows[0].duplicate, isFalse); // preview row is an expense
    });

    test('category inference (e12 §2): brands preselect, income stays silent',
        () async {
      final p = await preview();
      final byText = {for (final r in p.rows) r.description!: r};
      // 'Cafe Late' hits the brand table → Food, high, resolved to the
      // seeded category's id so commit persists it after review.
      final cafe = byText['Cafe Late']!;
      expect(cafe.categoryName, 'Food');
      expect(cafe.categoryConfidence, FieldConfidence.high);
      expect(cafe.categoryId, isNotNull);
      // Income rows are never inferred.
      expect(byText['Salary Corp']!.categoryName, isNull);
      // 'Corner Store' matches no vocabulary → silence, not a guess.
      expect(byText['Corner Store']!.categoryName, isNull);
      expect(byText['Corner Store']!.categoryConfidence, isNull);
    });

    test('item blocks survive commit into LineItems in document order '
        '(e12 §5)', () async {
      final parsed = StatementLines.tryParse(
        const [
          '12/05/2026 CITY HOSPITAL 250.00 4,300.00',
          'X-RAY READING 120.00',
          'LAB WORK 80.00',
          'SUPPLY FEE 50.00',
          'TOTAL CHARGES 250.00',
        ],
        currency: usd,
        now: DateTime.utc(2026, 12, 20),
      )!;
      expect(parsed.rows.single.items, hasLength(3));
      final preview = await CsvImport(db).previewStatement(
        accountId: accountId,
        currency: usd,
        rows: parsed.rows,
      );
      expect(preview.rows.single.items, hasLength(3));
      final n = await CsvImport(db).commit(
        accountId: accountId,
        currency: usd,
        rows: preview.rows,
      );
      expect(n, 1);
      final tx = (await repo.transactionsForMonth('2026-12')).single;
      final stored = await repo.lineItemsFor(tx.id);
      expect(stored.map((e) => e.name), ['X-RAY READING', 'LAB WORK', 'SUPPLY FEE']);
      expect(stored.map((e) => e.position), [0, 1, 2]);
      expect(
        stored.fold<int>(0, (s, e) => s + e.unitPriceMinor!),
        parsed.rows.single.minor,
      );
    });

    test('commit rides CsvImport.commit; re-preview flags everything',
      () async {
        final p = await preview();
        final n = await imp.commit(
          accountId: accountId,
          currency: usd,
          rows: p.rows,
        );
        expect(n, 3);
        final again = await preview();
        expect(again.rows.every((r) => r.duplicate), isTrue);
        expect(again.newCount, 0);
      },
    );
  });
}
