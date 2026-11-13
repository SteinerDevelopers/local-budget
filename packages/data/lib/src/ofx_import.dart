// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'package:core/core.dart';
import 'package:xml/xml.dart';

import 'csv_import.dart';
import 'database.dart';
import 'ledger_repository.dart';

/// A document the parser refuses outright (not XML, unknown currency…).
/// The wizard shows [message] verbatim — it must name the way out.
class OfxFormatException implements Exception {
  const OfxFormatException(this.message);
  final String message;
  @override
  String toString() => 'OfxFormatException: $message';
}

/// One STMTTRN as the ledger wants it: unsigned minor units + flag
/// (negative TRNAMT = expense, E5 §5), FITID kept for the v6 index.
class OfxTransaction {
  const OfxTransaction({
    required this.date,
    required this.minor,
    required this.isIncome,
    required this.fitId,
    required this.name,
    required this.memo,
  });

  final DateTime date;
  final int minor;
  final bool isIncome;
  final String? fitId;
  final String? name;
  final String? memo;
}

/// One parsed OFX statement: single currency (mixed-CURDEF files are
/// rejected — v1 imports one statement document at a time).
class OfxStatement {
  const OfxStatement({
    required this.currency,
    required this.accountRef,
    required this.transactions,
  });

  final Currency currency;

  /// BANKACCTFROM/ACCTID or CCACCTFROM/ACCTID when present — the wizard
  /// shows it so the user can confirm they picked the right account.
  final String? accountRef;
  final List<OfxTransaction> transactions;
}

/// DTPOSTED: `YYYYMMDD` with optional `HHMMSS[.sss]` and a bracketed or
/// inline timezone offset. Only the calendar date enters the ledger.
final RegExp _ofxDate = RegExp(r'^(\d{4})(\d{2})(\d{2})');

/// Parses OFX 1.x **XML** documents (E5 §5). SGML-style OFX — the classic
/// 1.x shape without closing tags — is detected and refused, never
/// half-parsed: it is not well-formed XML, so `XmlDocument.parse` throws
/// first and the message says exactly what was seen.
OfxStatement parseOfx(String text) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on FormatException catch (e) {
    // SGML-ish OFX (no closing tags) always fails here — well-formed XML
    // is the precondition this parser promises (E5 §5).
    throw OfxFormatException(
      'This OFX is not a well-formed XML document (${e.message}). '
      'SGML-style OFX 1.x files are not supported.',
    );
  }
  final root = doc.rootElement;
  if (root.name.local != 'OFX') {
    throw OfxFormatException(
      'Expected an <OFX> document, found <${root.name.local}>.',
    );
  }

  final curDefs = <String>{};
  for (final e in root.findAllElements('CURDEF')) {
    final v = e.innerText.trim();
    if (v.isNotEmpty) curDefs.add(v);
  }
  if (curDefs.isEmpty) {
    throw const OfxFormatException('No CURDEF (currency) in the document.');
  }
  if (curDefs.length > 1) {
    throw OfxFormatException(
      'Mixed currencies in one document (${curDefs.join(', ')}); '
      'import one statement at a time.',
    );
  }
  final code = curDefs.first;
  final currency = Currency.find(code);
  if (currency == null) {
    throw OfxFormatException(
      'Unsupported currency "$code" — the app only stores currencies it '
      'knows.',
    );
  }

  String? acctId;
  for (final e in root.findAllElements('ACCTID')) {
    final v = e.innerText.trim();
    if (v.isNotEmpty) {
      acctId = v;
      break;
    }
  }

  // Every STMTTRN must parse: a silently dropped row would corrupt
  // balances, so any unreadable row refuses the whole file (spec §4
  // preview philosophy, applied to a format the user cannot re-map).
  final problems = <String>[];
  final transactions = <OfxTransaction>[];
  var index = 0;
  for (final trn in root.findAllElements('STMTTRN')) {
    index++;
    String? field(String name) {
      for (final c in trn.childElements) {
        if (c.name.local == name) {
          final v = c.innerText.trim();
          if (v.isNotEmpty) return v;
        }
      }
      return null;
    }

    final rawDate = field('DTPOSTED');
    final rawAmount = field('TRNAMT');
    final match = rawDate == null ? null : _ofxDate.firstMatch(rawDate);
    final amount = rawAmount == null
        ? null
        : parseAmountCell(rawAmount, currency);
    if (match == null || amount == null) {
      problems.add(
        'row $index (${rawDate ?? 'no DTPOSTED'} / '
        '${rawAmount ?? 'no TRNAMT'})',
      );
      continue;
    }
    final day = DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    transactions.add(
      OfxTransaction(
        date: day,
        minor: amount.minor,
        isIncome: amount.isIncome,
        fitId: field('FITID'),
        name: field('NAME'),
        memo: field('MEMO'),
      ),
    );
  }
  if (problems.isNotEmpty) {
    throw OfxFormatException(
      'Unreadable statement rows: ${problems.join('; ')}. Nothing was '
      'imported — a skipped row would silently corrupt balances.',
    );
  }
  if (transactions.isEmpty) {
    throw const OfxFormatException('The document contains no STMTTRN rows.');
  }

  return OfxStatement(
    currency: currency,
    accountRef: acctId,
    transactions: transactions,
  );
}

/// OFX import behind the wizard (E5 §5): the document carries its own
/// currency, so the flow re-enters at Preview. Reuses the CSV preview
/// model so the wizard has exactly one screen for both formats.
class OfxImport {
  OfxImport(this.db);

  final AppDatabase db;

  Future<CsvPreview> buildPreview({
    required String xmlText,
    required int accountId,
  }) async {
    final statement = parseOfx(xmlText);
    final exists = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(accountId))).getSingleOrNull();
    if (exists == null) {
      throw ArgumentError.value(accountId, 'accountId', 'unknown account');
    }
    // Amounts are always in CURDEF — CsvPreview.currency carries the
    // *statement* currency; the wizard shows an amber note when it
    // differs from the account's.

    // FITID is the strongest key (v6 unique index): any row whose FITID
    // already exists for this account is a duplicate; rows without FITID
    // fall back to the conservative CSV tuple (E5 §4).
    final seenExternal = <String>{};
    final seenTuple = <String>{};
    final existing = await (db.select(
      db.transactions,
    )..where((t) => t.accountId.equals(accountId))).get();
    for (final t in existing) {
      final ext = t.externalId;
      if (ext != null) seenExternal.add(ext);
      seenTuple.add('${t.dateDays}|${t.amountMinor}|${t.isIncome}');
    }

    final fileSeen = <String>{};
    // e12 §2: OFX never carries categories either — the same deterministic
    // merchant suggestion the CSV preview uses, resolved against the user's
    // real categories so only an existing one is ever preselected.
    final cats = await db.select(db.categories).get();
    int? findCat(String? name) {
      final t = name?.trim().toLowerCase();
      if (t == null || t.isEmpty) return null;
      for (final c in cats) {
        if (!c.isIncome && c.name.toLowerCase() == t) return c.id;
      }
      return null;
    }

    final rows = <CsvPreviewRow>[];
    for (var i = 0; i < statement.transactions.length; i++) {
      final t = statement.transactions[i];
      final tuple = '${epochDayOf(t.date)}|${t.minor}|${t.isIncome}';
      final duplicate =
          (t.fitId != null &&
              (seenExternal.contains(t.fitId) ||
                  fileSeen.contains(t.fitId!))) ||
          (t.fitId == null &&
              (seenTuple.contains(tuple) || fileSeen.contains(tuple)));
      if (t.fitId != null) fileSeen.add(t.fitId!);
      fileSeen.add(tuple);
      final hint = t.isIncome ? null : CategoryHints.suggest(t.name ?? '');
      rows.add(
        CsvPreviewRow(
          rowIndex: i,
          date: t.date,
          minor: t.minor,
          isIncome: t.isIncome,
          description: t.name,
          categoryId: findCat(hint?.$1),
          categoryName: hint?.$1,
          categoryConfidence: hint?.$2,
          note: t.memo,
          externalId: t.fitId,
          duplicate: duplicate,
        ),
      );
    }
    return CsvPreview(
      rows: rows,
      errors: const [],
      currency: statement.currency,
      accountRef: statement.accountRef,
    );
  }

  /// Same batched commit as CSV (E5 §4) — the preview rows carry FITID in
  /// [CsvPreviewRow.externalId], and rows keep the document's CURDEF.
  Future<int> commit({
    required int accountId,
    required Currency currency,
    required List<CsvPreviewRow> rows,
    TransactionSource source = TransactionSource.statementImport,
  }) => CsvImport(db).commit(
    accountId: accountId,
    currency: currency,
    rows: rows,
    source: source,
  );
}
