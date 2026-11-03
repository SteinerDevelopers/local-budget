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
  final jpy = Currency.resolve('JPY');

  group('date formats', () {
    test('parseDateWithFormat is strict and range-checked', () {
      expect(
        parseDateWithFormat('2026-11-02', 'yyyy-MM-dd'),
        DateTime.utc(2026, 11, 2),
      );
      expect(
        parseDateWithFormat('2.11.2026', 'dd.MM.yyyy'),
        DateTime.utc(2026, 11, 2),
      );
      expect(
        parseDateWithFormat('11/02/2026', 'MM/dd/yyyy'),
        DateTime.utc(2026, 11, 2),
      );
      expect(
        parseDateWithFormat('11/02/2026', 'dd/MM/yyyy'),
        DateTime.utc(2026, 2, 11),
      );
      expect(parseDateWithFormat('31.02.2026', 'dd.MM.yyyy'), isNull);
      expect(parseDateWithFormat('2026-13-01', 'yyyy-MM-dd'), isNull);
      expect(parseDateWithFormat('2026/11/02', 'dd/MM/yyyy'), isNull);
      expect(
        parseDateWithFormat(' 2026-11-02 ', 'yyyy-MM-dd'),
        DateTime.utc(2026, 11, 2),
      );
    });

    test('detectDateFormat: unique, ambiguous, none', () {
      expect(
        detectDateFormat(['2026-11-02', '2026-01-31']).format,
        'yyyy-MM-dd',
      );
      expect(
        detectDateFormat(['5.11.2026', '31.12.2026']).format,
        'dd.MM.yyyy',
      );
      // 25 can never be a month ⇒ unambiguous day-first.
      expect(
        detectDateFormat(['05/04/2026', '25/04/2026']).format,
        'dd/MM/yyyy',
      );
      final amb = detectDateFormat(['05/04/2026']);
      expect(amb.format, isNull);
      expect(amb.ambiguous, isTrue);
      expect(detectDateFormat(['something']).format, isNull);
      expect(detectDateFormat([]).ambiguous, isFalse);
    });
  });

  group('header heuristics', () {
    test('spec examples map to the right roles', () {
      expect(guessRole('Date'), ImportRole.date);
      expect(guessRole('TransDate'), ImportRole.date);
      expect(guessRole('Posted'), ImportRole.date);
      expect(guessRole('Description'), ImportRole.description);
      expect(guessRole('Payee'), ImportRole.description);
      expect(guessRole('Merchant name'), ImportRole.description);
      expect(guessRole('Amount'), ImportRole.amount);
      expect(guessRole('Betrag (€)'), ImportRole.amount);
      expect(guessRole('Debit'), ImportRole.debit);
      expect(guessRole('Credit'), ImportRole.credit);
      expect(guessRole('Withdrawal'), ImportRole.debit);
      expect(guessRole('Deposit'), ImportRole.credit);
      expect(guessRole('Category'), ImportRole.category);
      expect(guessRole('Memo'), ImportRole.note);
      expect(guessRole('Account no.'), ImportRole.ignore);
    });

    test('"credit amount" is credit, not the amount fallback', () {
      expect(guessRole('Credit Amount'), ImportRole.credit);
    });
  });

  group('amount parsing', () {
    test(
      'sign rule mirrors the exporter: neg=expense, pos=income, zero=expense',
      () {
        expect(parseAmountCell('-12.34', usd), (minor: 1234, isIncome: false));
        expect(parseAmountCell('12.34', usd), (minor: 1234, isIncome: true));
        expect(parseAmountCell('0.00', usd), (minor: 0, isIncome: false));
        expect(parseAmountCell('-0.00', usd), (minor: 0, isIncome: false));
      },
    );

    test('both decimal styles, both groupings, bank notations', () {
      expect(parseAmountCell('1,234.56', usd), (minor: 123456, isIncome: true));
      expect(parseAmountCell('1.234,56', usd), (minor: 123456, isIncome: true));
      expect(parseAmountCell('12,34', usd), (minor: 1234, isIncome: true));
      expect(parseAmountCell('1.234', usd), (minor: 123400, isIncome: true));
      expect(parseAmountCell('12.34-', usd), (minor: 1234, isIncome: false));
      expect(parseAmountCell('(12.34)', usd), (minor: 1234, isIncome: false));
      expect(parseAmountCell('EUR 12.34', usd), (minor: 1234, isIncome: true));
      expect(parseAmountCell(' 12.34 ', usd), (minor: 1234, isIncome: true));
    });

    test('exponent-aware: JPY refuses cents, never guesses precision', () {
      expect(parseAmountCell('1234', jpy), (minor: 1234, isIncome: true));
      expect(parseAmountCell('1234.56', jpy), isNull);
      expect(parseAmountCell('1,234', jpy), (minor: 1234, isIncome: true));
    });

    test('garbage and bad grouping return null', () {
      expect(parseAmountCell('', usd), isNull);
      expect(parseAmountCell('abc', usd), isNull);
      expect(parseAmountCell('12.3.45', usd), isNull);
      expect(parseAmountCell('12,34,567', usd), isNull);
      expect(parseAmountCell('--12', usd), isNull);
    });
  });

  group('csv import', () {
    late AppDatabase db;
    late LedgerRepository repo;
    late CsvImport imp;
    late int accountId;

    setUp(() async {
      db = AppDatabase.inMemory();
      repo = LedgerRepository(db);
      imp = CsvImport(db);
      accountId = await repo.createAccount(
        name: 'Checking',
        currencyCode: 'USD',
      );
    });
    tearDown(() => db.close());

    Future<void> seedTx({
      required DateTime date,
      required String amount,
      bool isIncome = false,
      String? merchant,
    }) => repo.addTransaction(
      accountId: accountId,
      date: date,
      amount: Money.tryParse(amount, usd)!,
      source: TransactionSource.manual,
      merchant: merchant,
      isIncome: isIncome,
    );

    CsvMapping autoOf(CsvFileData f) => imp.autoMap(f);

    test('autoMap + preview + commit, dedupe conservative', () async {
      await seedTx(
        date: DateTime(2026, 10, 30),
        amount: '12.34',
        merchant: 'Corner Store',
      );
      final file = CsvFileData(
        'date,description,amount\n'
        '2026-10-30,Corner Store,-12.34\n' // the existing one → duplicate
        '2026-11-01,Salary Corp,2 500.00\n' // income
        '2026-11-02,"Café, ""Late""",-3.50\n' // quoted+embedded comma, expense
        'nonsense,Bad row,-1.00\n', // unreadable date
      );
      final mapping = autoOf(file);
      expect(mapping.roles.take(3), [
        ImportRole.date,
        ImportRole.description,
        ImportRole.amount,
      ]);
      expect(mapping.dateFormat, 'yyyy-MM-dd');

      final preview = await imp.buildPreview(
        file: file,
        mapping: mapping,
        accountId: accountId,
      );
      expect(preview.newCount, 2);
      expect(preview.duplicateCount, 1);
      expect(preview.errors.single.reason, 'unreadable date');
      final salary = preview.rows.firstWhere(
        (r) => r.description == 'Salary Corp',
      );
      expect(salary.isIncome, isTrue);
      expect(salary.minor, 250000); // space-grouped thousands
      expect(
        preview.rows.firstWhere((r) => r.duplicate).description,
        'Corner Store',
      );

      final n = await imp.commit(
        accountId: accountId,
        currency: usd,
        rows: preview.rows.where((r) => !r.duplicate).toList(),
      );
      expect(n, 2);
      final rows = await repo.transactionsForMonth(
        '2026-11',
        accountId: accountId,
      );
      expect(rows, hasLength(2));
      expect(rows.firstWhere((r) => r.isIncome).amountMinor, 250000);
      final merchants = await repo.merchantsLike('Café', limit: 5);
      expect(merchants, contains('Café, "Late"'));
    });

    test('duplicates can be force-included, never silently dropped', () async {
      await seedTx(date: DateTime(2026, 10, 30), amount: '12.34');
      final file = CsvFileData(
        'date,description,amount\n2026-10-30,Dup,-12.34\n',
      );
      final preview = await imp.buildPreview(
        file: file,
        mapping: autoOf(file),
        accountId: accountId,
      );
      expect(preview.rows.single.duplicate, isTrue);
      expect(preview.newCount, 0);
      final n = await imp.commit(
        accountId: accountId,
        currency: usd,
        rows: preview.rows, // user checked the duplicate anyway
      );
      expect(n, 1);
    });

    test('debit/credit split columns with polarity', () async {
      final file = CsvFileData(
        'date,description,debit,credit\n'
        '2026-11-01,Shop,10.00,\n'
        '2026-11-02,Refund,,5.00\n'
        '2026-11-03,Both,1.00,1.00\n' // ambiguous side-by-side → error
        '2026-11-04,Neither,,\n',
      );
      final mapping = autoOf(file);
      final preview = await imp.buildPreview(
        file: file,
        mapping: mapping,
        accountId: accountId,
      );
      expect(preview.rows, hasLength(2));
      expect(preview.errors, hasLength(2));
      final shop = preview.rows.first;
      expect(shop.isIncome, isFalse);
      expect(preview.rows[1].isIncome, isTrue);
      // Flipped polarity card statement: debit is income, credit expense.
      final flipped = await imp.buildPreview(
        file: file,
        mapping: CsvMapping(
          roles: mapping.roles,
          dateFormat: mapping.dateFormat,
          debitMeansExpense: false,
        ),
        accountId: accountId,
      );
      expect(flipped.rows.first.isIncome, isTrue);
      expect(flipped.rows[1].isIncome, isFalse);
    });

    test(
      'dd.MM.yyyy German statement with decimal comma round-trips',
      () async {
        final file = CsvFileData(
          'Buchungsdatum;Verwendungszweck;Betrag (€)\n'
          '02.11.2026;Brötchen;3,50\n'
          '01.11.2026;Gehalt;-2.450,00\n',
        );
        expect(file.delimiter, ';');
        final mapping = autoOf(file);
        expect(mapping.dateFormat, 'dd.MM.yyyy');
        final preview = await imp.buildPreview(
          file: file,
          mapping: mapping,
          accountId: accountId,
        );
        expect(preview.rows, hasLength(2));
        final brot = preview.rows.firstWhere(
          (r) => r.description == 'Brötchen',
        );
        expect((brot.minor, brot.isIncome), (350, true)); // +3,50 = income sign
        final gehalt = preview.rows.firstWhere(
          (r) => r.description == 'Gehalt',
        );
        expect((gehalt.minor, gehalt.isIncome), (245000, false));
      },
    );

    test('export output re-imports as 100% duplicates', () async {
      await seedTx(
        date: DateTime(2026, 11, 1),
        amount: '12.34',
        merchant: 'Corner Store',
      );
      await seedTx(
        date: DateTime(2026, 11, 2),
        amount: '100.00',
        isIncome: true,
        merchant: 'Salary',
      );
      await seedTx(date: DateTime(2026, 11, 3), amount: '0.00');
      final csv = await CsvExport(db).build(accountId: accountId);
      final file = CsvFileData(csv);
      final mapping = autoOf(file);
      final preview = await imp.buildPreview(
        file: file,
        mapping: mapping,
        accountId: accountId,
      );
      expect(preview.errors, isEmpty);
      expect(preview.duplicateCount, 3);
      expect(preview.newCount, 0);
    });

    test('profiles save, match exactly, manage, survive corruption', () async {
      final file = CsvFileData('date,description,amount\n2026-11-01,X,-1.00\n');
      final mapping = autoOf(file);
      await imp.saveProfile(name: 'My Bank', file: file, mapping: mapping);
      expect(await imp.profileNames(), ['My Bank']);

      final match = await imp.profileMatching(file.headerRow);
      expect(match?.name, 'My Bank');
      expect(match?.mapping.roles, mapping.roles);
      expect(match?.mapping.dateFormat, 'yyyy-MM-dd');

      // Different header ⇒ no match (spec: exact match only).
      expect(await imp.profileMatching(['date', 'amount']), isNull);

      // Corruption behaves like no profile, never throws.
      await repo.setSetting(CsvImport.profileKeyPrefix + 'Broken', '{oops');
      expect(await imp.loadProfile('Broken'), isNull);

      await imp.deleteProfile('My Bank');
      expect(await imp.profileNames(), ['Broken']); // listed but unusable
      expect(await imp.profileMatching(file.headerRow), isNull);
    });

    test(
      'category role resolves existing categories by name, sign-aware',
      () async {
        final food = await repo.addCategory('Food');
        final salaryCat = await repo.addCategory('Salary', isIncome: true);
        final file = CsvFileData(
          'date,amount,category\n'
          '2026-11-01,-9.99,food\n' // case-insensitive
          '2026-11-02,90.00,Salary\n'
          '2026-11-03,-1.00,Nope\n', // unknown → uncategorized, still imported
        );
        final preview = await imp.buildPreview(
          file: file,
          mapping: autoOf(file),
          accountId: accountId,
        );
        expect(preview.rows.first.categoryId, food);
        expect(preview.rows[1].categoryId, salaryCat);
        expect(preview.rows[2].categoryId, isNull);
        expect(preview.rows[2].categoryName, 'Nope');
        final n = await imp.commit(
          accountId: accountId,
          currency: usd,
          rows: preview.rows,
        );
        expect(n, 3);
        final rows = await repo.transactionsForMonth(
          '2026-11',
          accountId: accountId,
        );
        expect(rows.firstWhere((r) => r.note == null).categoryId, isNotNull);
      },
    );
  });
}
