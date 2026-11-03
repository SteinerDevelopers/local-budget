import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

/// Well-formed OFX 1.x XML — the only shape the parser accepts (E5 §5).
const bankOfx = '''
<?xml version="1.0" encoding="UTF-8"?>
<OFX>
  <BANKMSGSRSV1>
    <STMTTRNR>
      <STMTRS>
        <CURDEF>USD</CURDEF>
        <BANKACCTFROM>
          <BANKID>121000359</BANKID><ACCTID>000123</ACCTID>
        </BANKACCTFROM>
        <BANKTRANLIST>
          <DTSTART>20261101</DTSTART><DTEND>20261102</DTEND>
          <STMTTRN>
            <TRNTYPE>DEBIT</TRNTYPE>
            <DTPOSTED>20261102</DTPOSTED>
            <TRNAMT>-3.50</TRNAMT>
            <FITID>TXN0001</FITID>
            <NAME>CAFE LATE</NAME><MEMO>latte</MEMO>
          </STMTTRN>
          <STMTTRN>
            <TRNTYPE>CREDIT</TRNTYPE>
            <DTPOSTED>20261101120000[-06:00]</DTPOSTED>
            <TRNAMT>2450.00</TRNAMT>
            <FITID>PAY0001</FITID>
            <NAME>ACME CORP PAYROLL</NAME>
          </STMTTRN>
        </BANKTRANLIST>
      </STMTRS>
    </STMTTRNR>
  </BANKMSGSRSV1>
</OFX>
''';

/// Classic 1.x SGML: tags never close. Must be refused, never
/// half-parsed (issue wording "standard XML").
const sgmlOfx = '''
OFXHEADER:100
DATA:BANKSTMT
VERSION:102
<OFX><BANKMSGSRSV1><STMTTRNR><STMTRS><CURDEF>USD</CURDEF>
<BANKTRANLIST><STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261102<TRNAMT>-3.50
<FITID>TXN0001<NAME>CAFE LATE
</STMTRS></STMTTRNR></BANKMSGSRSV1></OFX>
''';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');

  group('parseOfx', () {
    test('reads a well-formed 1.x XML statement', () {
      final s = parseOfx(bankOfx);
      expect(s.currency.code, 'USD');
      expect(s.accountRef, '000123');
      expect(s.transactions.length, 2);

      final debit = s.transactions.first;
      expect(debit.date, DateTime.utc(2026, 11, 2));
      // Negative TRNAMT = expense → unsigned amount + flag (spec §5).
      expect(debit.isIncome, isFalse);
      expect(debit.minor, 350);
      expect(debit.fitId, 'TXN0001');
      expect(debit.name, 'CAFE LATE');
      expect(debit.memo, 'latte');

      final credit = s.transactions[1];
      expect(credit.isIncome, isTrue);
      expect(credit.minor, 245000);
      // DTPOSTED with time + bracketed tz still resolves to one day.
      expect(credit.date, DateTime.utc(2026, 11, 1));
    });

    test('SGML-ish OFX is refused, not half-parsed', () {
      expect(
        () => parseOfx(sgmlOfx),
        throwsA(
          isA<OfxFormatException>().having(
            (e) => e.message,
            'message',
            contains('SGML'),
          ),
        ),
      );
    });

    test('unknown currency is refused', () {
      final s = bankOfx.replaceAll('<CURDEF>USD', '<CURDEF>XYZ');
      expect(
        () => parseOfx(s),
        throwsA(
          isA<OfxFormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported currency'),
          ),
        ),
      );
    });

    test('unreadable row refuses the whole file', () {
      final s = bankOfx.replaceAll('<TRNAMT>-3.50', '<TRNAMT>three fifty');
      expect(
        () => parseOfx(s),
        throwsA(
          isA<OfxFormatException>().having(
            (e) => e.message,
            'message',
            contains('Unreadable statement rows'),
          ),
        ),
      );
    });

    test('empty statement is refused', () {
      final s = bankOfx.replaceAll(
        RegExp(r'<STMTTRN>.*?</STMTTRN>', dotAll: true),
        '',
      );
      expect(() => parseOfx(s), throwsA(isA<OfxFormatException>()));
    });

    test('non-OFX root is refused', () {
      expect(
        () => parseOfx('<?xml version="1.0"?><QIF></QIF>'),
        throwsA(
          isA<OfxFormatException>().having(
            (e) => e.message,
            'message',
            contains('<OFX>'),
          ),
        ),
      );
    });
  });

  group('OfxImport', () {
    late AppDatabase db;
    late LedgerRepository repo;
    late int accountId;
    late OfxImport ofx;

    setUp(() async {
      db = AppDatabase.inMemory();
      repo = LedgerRepository(db);
      ofx = OfxImport(db);
      accountId = await repo.createAccount(
        name: 'Checking',
        currencyCode: 'USD',
      );
    });
    tearDown(() => db.close());

    test('preview + commit writes FITIDs and statementImport source', () async {
      final preview = await ofx.buildPreview(
        xmlText: bankOfx,
        accountId: accountId,
      );
      expect(preview.currency.code, 'USD');
      expect(preview.accountRef, '000123');
      expect(preview.newCount, 2);
      expect(preview.duplicateCount, 0);

      final n = await ofx.commit(
        accountId: accountId,
        currency: preview.currency,
        rows: preview.rows,
      );
      expect(n, 2);

      final rows = await db.select(db.transactions).get();
      expect(rows.length, 2);
      final byExternal = {for (final r in rows) r.externalId: r};
      expect(byExternal['TXN0001'], isNotNull);
      expect(byExternal['TXN0001']!.amountMinor, 350);
      expect(byExternal['TXN0001']!.isIncome, isFalse);
      expect(byExternal['PAY0001']!.isIncome, isTrue);
      expect(
        rows.map((r) => r.source),
        everyElement(TransactionSource.statementImport),
      );
      // Merchant from NAME, note from MEMO.
      expect(byExternal['TXN0001']!.note, 'latte');
    });

    test('re-import dedupes on FITID (incremental import)', () async {
      final first = await ofx.buildPreview(
        xmlText: bankOfx,
        accountId: accountId,
      );
      await ofx.commit(
        accountId: accountId,
        currency: first.currency,
        rows: first.rows,
      );

      // Same file again: everything is a duplicate.
      final again = await ofx.buildPreview(
        xmlText: bankOfx,
        accountId: accountId,
      );
      expect(again.newCount, 0);
      expect(again.duplicateCount, 2);

      // Bank adds one new transaction and repeats the old ones.
      final extended = bankOfx.replaceAll(
        '</BANKTRANLIST>',
        '<STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20261103</DTPOSTED>'
            '<TRNAMT>-9.99</TRNAMT><FITID>TXN0002</FITID>'
            '<NAME>BOOKSTORE</NAME></STMTTRN></BANKTRANLIST>',
      );
      final next = await ofx.buildPreview(
        xmlText: extended,
        accountId: accountId,
      );
      expect(next.newCount, 1);
      expect(next.duplicateCount, 2);
      expect(
        await ofx.commit(
          accountId: accountId,
          currency: next.currency,
          rows: next.rows.where((r) => !r.duplicate).toList(),
        ),
        1,
      );
    });

    test('rows without FITID fall back to the tuple dedupe', () async {
      final noFit = bankOfx.replaceAll(
        RegExp(r'<FITID>[^<]*</FITID>\s*', multiLine: true),
        '',
      );
      final first = await ofx.buildPreview(
        xmlText: noFit,
        accountId: accountId,
      );
      expect(first.newCount, 2);
      await ofx.commit(
        accountId: accountId,
        currency: first.currency,
        rows: first.rows,
      );
      final again = await ofx.buildPreview(
        xmlText: noFit,
        accountId: accountId,
      );
      expect(again.duplicateCount, 2);
    });

    test('duplicate FITID inside one file is flagged', () async {
      final dup = bankOfx.replaceAll('PAY0001', 'TXN0001');
      final preview = await ofx.buildPreview(
        xmlText: dup,
        accountId: accountId,
      );
      expect(preview.newCount, 1);
      expect(preview.duplicateCount, 1);
    });

    test('the v6 unique index is the hard backstop', () async {
      await repo.addTransaction(
        accountId: accountId,
        date: DateTime.utc(2026, 11, 2),
        amount: Money(350, usd),
        source: TransactionSource.statementImport,
        externalId: 'DUP',
      );
      await expectLater(
        repo.addTransaction(
          accountId: accountId,
          date: DateTime.utc(2026, 11, 2),
          amount: Money(350, usd),
          source: TransactionSource.statementImport,
          externalId: 'DUP',
        ),
        throwsA(isA<sqlite3.SqliteException>()),
      );
      // Same FITID on another account is fine (index is per-account).
      final other = await repo.createAccount(
        name: 'Savings',
        currencyCode: 'USD',
      );
      await repo.addTransaction(
        accountId: other,
        date: DateTime.utc(2026, 11, 2),
        amount: Money(350, usd),
        source: TransactionSource.statementImport,
        externalId: 'DUP',
      );
      // NULL external ids never collide.
      for (var i = 0; i < 2; i++) {
        await repo.addTransaction(
          accountId: accountId,
          date: DateTime.utc(2026, 11, 2),
          amount: Money(100, usd),
          source: TransactionSource.manual,
        );
      }
    });

    test('statement currency travels with the rows', () async {
      final eur = bankOfx.replaceAll('<CURDEF>USD', '<CURDEF>EUR');
      final preview = await ofx.buildPreview(
        xmlText: eur,
        accountId: accountId,
      );
      // Amounts keep the document's currency (account stays USD; the
      // wizard flags the mismatch visually in E5 §6/§7 UI work).
      expect(preview.currency.code, 'EUR');
      await ofx.commit(
        accountId: accountId,
        currency: preview.currency,
        rows: preview.rows,
      );
      final rows = await db.select(db.transactions).get();
      expect(rows.first.currencyCode, 'EUR');
    });
  });
}
