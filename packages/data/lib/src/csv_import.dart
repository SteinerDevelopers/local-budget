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

import 'dart:convert';

import 'package:core/core.dart';
import 'package:drift/drift.dart';

import 'csv_codec.dart';
import 'database.dart';
import 'ledger_repository.dart';
import 'statement_lines.dart';

/// Column roles the import wizard can map a CSV column to (E5 spec §4).
enum ImportRole {
  date('date'),
  description('description'),
  amount('amount'),
  debit('debit'),
  credit('credit'),
  category('category'),
  note('note'),
  ignore('ignore');

  const ImportRole(this.wireName);

  /// Stable name inside saved mapping profiles — never rename, stored.
  final String wireName;

  static ImportRole? fromWire(String name) {
    for (final r in ImportRole.values) {
      if (r.wireName == name) return r;
    }
    return null;
  }
}

/// Supported bank date formats (spec §4). Detection only ever picks one of
/// these; anything else asks the user instead of guessing.
const csvDateFormats = ['yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd.MM.yyyy'];

/// Strict parse of [raw] under one of [csvDateFormats]; null on any
/// mismatch (range-checked, no Dart sloppiness).
DateTime? parseDateWithFormat(String raw, String format) {
  final s = raw.trim();
  final RegExp re;
  final int yPart, mPart, dPart;
  switch (format) {
    case 'yyyy-MM-dd':
      re = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
      yPart = 1;
      mPart = 2;
      dPart = 3;
    case 'dd/MM/yyyy':
      re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
      yPart = 3;
      mPart = 2;
      dPart = 1;
    case 'MM/dd/yyyy':
      re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
      yPart = 3;
      mPart = 1;
      dPart = 2;
    case 'dd.MM.yyyy':
      re = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');
      yPart = 3;
      mPart = 2;
      dPart = 1;
    default:
      return null;
  }
  final m = re.firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(yPart)!);
  final mo = int.parse(m.group(mPart)!);
  final d = int.parse(m.group(dPart)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime.utc(y, mo, d);
  // Reject overflow like 31.02.2026 rolling into March.
  if (dt.day != d || dt.month != mo) return null;
  return dt;
}

/// Guess the date format from sample values. Returns exactly one candidate
/// when every sample parses under exactly one format; [ambiguous] when more
/// than one format fits (UI must ask); null format when none fits.
({String? format, bool ambiguous}) detectDateFormat(List<String> samples) {
  final usable = samples
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (usable.isEmpty) return (format: null, ambiguous: false);
  final fits = <String>[
    for (final f in csvDateFormats)
      if (usable.every((s) => parseDateWithFormat(s, f) != null)) f,
  ];
  if (fits.length == 1) return (format: fits.first, ambiguous: false);
  return (format: null, ambiguous: fits.isNotEmpty);
}

/// Header-name heuristics from the spec (`date|transdate…`,
/// `description|payee…`, `amount|debit…`). Order matters: `credit amount`
/// must land on credit, not the generic amount fallback.
ImportRole guessRole(String header) {
  final h = header.toLowerCase();
  bool has(List<String> keys) => keys.any(h.contains);
  if (has(['date', 'posted', 'datum'])) return ImportRole.date;
  if (h.contains('debit') || h.contains('withdraw')) return ImportRole.debit;
  if (h.contains('credit') || h.contains('deposit')) return ImportRole.credit;
  if (has(['amount', 'amt', 'value', 'total', 'betrag'])) {
    return ImportRole.amount;
  }
  if (has(['categor', 'type'])) return ImportRole.category;
  if (has(['note', 'memo', 'comment'])) return ImportRole.note;
  if (has([
    'description',
    'payee',
    'merchant',
    'reference',
    'details',
    'verwendungszweck',
    'titel',
  ])) {
    return ImportRole.description;
  }
  return ImportRole.ignore;
}

/// Maps one amount cell to unsigned minor units under the §sign rule:
/// negative ⇒ expense (isIncome=false), positive ⇒ income, zero ⇒ expense
/// (mirrors the exporter, so export→import round-trips). Handles both
/// decimal styles and both grouping styles, trailing-minus bank notation,
/// and ISO-code/space noise. Null when the cell is not an amount.
({int minor, bool isIncome})? parseAmountCell(String raw, Currency currency) {
  var s = raw.trim().replaceAll('\u00a0', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  } else if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  if (s.startsWith('+')) s = s.substring(1);
  // Strip any letters left over (currency codes like EUR12,34 or 12,34EUR).
  s = s.replaceAll(RegExp(r'[A-Za-z]'), '');
  if (s.isEmpty) return null;

  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  String digits;
  int fracDigits;
  if (lastComma >= 0 && lastDot >= 0) {
    // Both present: the later separator is the decimal mark.
    final decAt = lastComma > lastDot ? lastComma : lastDot;
    digits = s.replaceAll(',', '').replaceAll('.', '');
    fracDigits = s.length - decAt - 1;
    if (_groupingMismatch(s, decAt)) return null;
  } else if (lastComma >= 0 || lastDot >= 0) {
    final sep = lastComma >= 0 ? lastComma : lastDot;
    final tail = s.length - sep - 1;
    // Groups of three after the separator are thousands separators — but
    // only when every earlier same-style group is also exactly three.
    if (tail == 3 && !_groupingMismatch(s, sep)) {
      digits = s.replaceAll(',', '').replaceAll('.', '');
      fracDigits = 0;
    } else {
      digits = '${s.substring(0, sep)}${s.substring(sep + 1)}';
      fracDigits = tail;
    }
  } else {
    digits = s;
    fracDigits = 0;
  }
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;
  if (fracDigits > currency.minorUnits) return null; // never guess precision
  var minor = int.parse(digits);
  for (var i = 0; i < currency.minorUnits - fracDigits; i++) {
    minor *= 10;
  }
  // Zero has no sign of its own: expense, matching the exporter.
  final isIncome = !negative && minor != 0;
  return (minor: minor, isIncome: isIncome);
}

/// True when separators left of [decAt] do not split the integer part into
/// a leading 1–3 digit group plus full groups of three ('12,34,567' style
/// garbage must not be mistaken for a thousands separator).
bool _groupingMismatch(String s, int decAt) {
  final intPart = s.substring(0, decAt);
  for (final sep in [',', '.']) {
    final segs = intPart.split(sep);
    if (segs.length == 1) continue;
    if (segs.first.isEmpty || segs.first.length > 3) return true;
    for (final g in segs.skip(1)) {
      if (g.length != 3) return true;
    }
  }
  return false;
}

/// One parsed-but-unmapped problem row (skipped from the import).
class CsvImportError {
  const CsvImportError(this.rowIndex, this.reason);
  final int rowIndex;
  final String reason;
}

/// One candidate transaction derived from a CSV row (spec §4 preview list).
class CsvPreviewRow {
  const CsvPreviewRow({
    required this.rowIndex,
    required this.date,
    required this.minor,
    required this.isIncome,
    this.description,
    this.categoryId,
    this.categoryName,
    this.categoryConfidence,
    this.note,
    this.externalId,
    this.items,
    this.duplicate = false,
  });

  final int rowIndex;
  final DateTime date;
  final int minor;
  final bool isIncome;
  final String? description;
  final int? categoryId;
  final String? categoryName;

  /// Set only when the category was *inferred* (e12 §2) — [FieldConfidence.medium]
  /// renders as a visible "?" in the preview; null means the row's category
  /// came from the file itself.
  final FieldConfidence? categoryConfidence;
  final String? note;

  /// OFX FITID when the row came from a statement import (E5 §5); CSV
  /// rows leave it null, where dedupe uses the tuple key instead.
  final String? externalId;

  /// Same (accountId, dateDays, amountMinor, isIncome) exists in the ledger.
  final bool duplicate;

  /// Reconciled item lines from a scanned statement (e12 §5); stored under
  /// the committed transaction. Null for files and non-reconciling scans.
  final List<ItemLine>? items;

  CsvPreviewRow copyWith({int? categoryId, bool? duplicate}) => CsvPreviewRow(
    rowIndex: rowIndex,
    date: date,
    minor: minor,
    isIncome: isIncome,
    description: description,
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName,
    categoryConfidence: categoryConfidence,
    note: note,
    externalId: externalId,
    items: items,
    duplicate: duplicate ?? this.duplicate,
  );
}

/// Full preview state: every row is either a candidate or an error.
class CsvPreview {
  const CsvPreview({
    required this.rows,
    required this.errors,
    required this.currency,
    this.accountRef,
  });

  final List<CsvPreviewRow> rows;
  final List<CsvImportError> errors;
  final Currency currency;

  /// OFX BANKACCTFROM/ACCTID shown on the Preview so the user can confirm
  /// the account they picked matches the file (E5 §5); null for CSV.
  final String? accountRef;

  int get newCount => rows.where((r) => !r.duplicate).length;
  int get duplicateCount => rows.where((r) => r.duplicate).length;
}

/// The user's column choices for one file (wizard Map step).
class CsvMapping {
  const CsvMapping({
    required this.roles,
    this.dateFormat,
    this.debitMeansExpense = true,
  });

  /// Parallel to the header row; length must match.
  final List<ImportRole> roles;
  final String? dateFormat;

  /// Polarity toggle persisted in profiles: some cards flip debit/credit.
  final bool debitMeansExpense;

  int? indexOf(ImportRole role) {
    for (var i = 0; i < roles.length; i++) {
      if (roles[i] == role) return i;
    }
    return null;
  }

  List<int> indexesOf(ImportRole role) => [
    for (var i = 0; i < roles.length; i++)
      if (roles[i] == role) i,
  ];
}

/// A saved per-bank mapping profile (settings KV `import.csv.<name>`).
class CsvProfile {
  const CsvProfile({
    required this.name,
    required this.headerRow,
    required this.mapping,
  });

  final String name;
  final List<String> headerRow;
  final CsvMapping mapping;

  static const keyPrefix = 'import.csv.';

  Map<String, Object?> toJson() => {
    'headerRow': headerRow,
    'roles': mapping.roles.map((r) => r.wireName).toList(),
    'dateFormat': mapping.dateFormat,
    'debitMeansExpense': mapping.debitMeansExpense,
  };

  /// Throws [FormatException] on a malformed stored value — profiles are
  /// written by this class only, so anything else is corruption.
  static CsvProfile fromJson(String name, Object? json) {
    if (json is! Map) throw const FormatException('profile is not an object');
    final header = json['headerRow'];
    final roles = json['roles'];
    if (header is! List || roles is! List) {
      throw const FormatException('profile missing headerRow/roles');
    }
    final parsed = [
      for (final r in roles)
        ImportRole.fromWire('$r') ??
            (throw FormatException('unknown role in profile: $r')),
    ];
    if (parsed.length != header.length) {
      throw const FormatException('profile roles/header length mismatch');
    }
    final fmt = json['dateFormat'];
    return CsvProfile(
      name: name,
      headerRow: header.map((e) => '$e').toList(),
      mapping: CsvMapping(
        roles: parsed,
        dateFormat: csvDateFormats.contains(fmt) ? '$fmt' : null,
        debitMeansExpense: json['debitMeansExpense'] != false,
      ),
    );
  }
}

/// Header + data rows of one CSV file (parser per E5 §2: RFC 4180, sniffed
/// delimiter).
class CsvFileData {
  CsvFileData(String text)
    : delimiter = sniffDelimiter(_firstLine(text)),
      rows = decodeCsv(text, delimiter: sniffDelimiter(_firstLine(text)));

  final String delimiter;
  final List<List<String>> rows;

  List<String> get headerRow => rows.isEmpty ? const [] : rows.first;
  List<List<String>> get dataRows =>
      rows.length < 2 ? const [] : rows.sublist(1);

  /// Sniffing sees only the header line: quote parity across a whole file
  /// is not guaranteed (and counting separators everywhere would skew it).
  static String _firstLine(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 10 || c == 13) return text.substring(0, i);
    }
    return text;
  }
}

/// The CSV import core behind the wizard (E5 spec §4): auto-mapping,
/// preview with conservative dedupe, batched commit, saved profiles.
class CsvImport {
  CsvImport(this.db);

  final AppDatabase db;
  LedgerRepository get _repo => LedgerRepository(db);

  static const profileKeyPrefix = CsvProfile.keyPrefix;

  // ---- profiles -----------------------------------------------------------

  Future<List<String>> profileNames() async {
    final rows = await (db.select(
      db.settings,
    )..where((t) => t.key.like('$profileKeyPrefix%'))).get();
    final names =
        rows
            .map((r) => r.key.substring(profileKeyPrefix.length))
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort();
    return names;
  }

  Future<CsvProfile?> loadProfile(String name) async {
    final raw = await _repo.setting('$profileKeyPrefix$name');
    if (raw == null) return null;
    try {
      return CsvProfile.fromJson(name, jsonDecode(raw));
    } on FormatException {
      return null; // corrupt entry behaves like no profile
    }
  }

  Future<void> saveProfile({
    required String name,
    required CsvFileData file,
    required CsvMapping mapping,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('profile name required');
    final profile = CsvProfile(
      name: trimmed,
      headerRow: file.headerRow,
      mapping: mapping,
    );
    await _repo.setSetting(
      '$profileKeyPrefix$trimmed',
      jsonEncode(profile.toJson()),
    );
  }

  Future<void> deleteProfile(String name) => (db.delete(
    db.settings,
  )..where((t) => t.key.equals('$profileKeyPrefix$name'))).go();

  /// Exact header-row match ⇒ the profile applies with one tap (spec §4).
  Future<CsvProfile?> profileMatching(List<String> headerRow) async {
    for (final name in await profileNames()) {
      final p = await loadProfile(name);
      if (p != null && _sameHeader(p.headerRow, headerRow)) return p;
    }
    return null;
  }

  static bool _sameHeader(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) => a[i].trim() == b[i].trim(),
      ).every((ok) => ok);

  // ---- mapping -------------------------------------------------------------

  /// Prefill roles from headers and the date format from up to 20 samples.
  /// No guessing beyond the heuristics: a missing date role stays missing
  /// (the Map step shows it empty and the user picks), an undetectable or
  /// ambiguous format falls back to ISO *visibly* — rows that then fail to
  /// parse surface as preview errors, never as silent mis-dates.
  CsvMapping autoMap(CsvFileData file) {
    final roles = [for (final h in file.headerRow) guessRole(h)];
    final dateAt = roles.indexOf(ImportRole.date);
    final fmt = detectDateFormat([
      for (final row in file.dataRows.take(20))
        if (dateAt >= 0 && dateAt < row.length) row[dateAt],
    ]);
    return CsvMapping(
      roles: roles,
      dateFormat: fmt.format ?? csvDateFormats.first,
    );
  }

  // ---- preview -------------------------------------------------------------

  Future<CsvPreview> buildPreview({
    required CsvFileData file,
    required CsvMapping mapping,
    required int accountId,
  }) async {
    final account = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(accountId))).getSingle();
    final currency = Currency.resolve(account.currencyCode);

    final dateAt = mapping.indexOf(ImportRole.date);
    final descAt = mapping.indexOf(ImportRole.description);
    final catAt = mapping.indexOf(ImportRole.category);
    final noteAt = mapping.indexOf(ImportRole.note);
    final amountAt = mapping.indexOf(ImportRole.amount);
    final debitAt = mapping.indexOf(ImportRole.debit);
    final creditAt = mapping.indexOf(ImportRole.credit);
    final dateFormat = mapping.dateFormat;
    if (dateAt == null || dateFormat == null) {
      throw ArgumentError('mapping needs a date column and a date format');
    }
    if (amountAt == null && debitAt == null && creditAt == null) {
      throw ArgumentError('mapping needs an amount or debit/credit column');
    }

    // Category lookup by display name, case-insensitive, expense vs income
    // picked by the row's sign.
    final cats = await _repo.categories();
    int? findCat(String? name, {required bool income}) {
      final t = name?.trim().toLowerCase();
      if (t == null || t.isEmpty) return null;
      for (final c in cats) {
        if (c.name.toLowerCase() == t && c.isIncome == income) return c.id;
      }
      return null;
    }

    final existing = await _dedupKeys(accountId);
    final rows = <CsvPreviewRow>[];
    final errors = <CsvImportError>[];
    final data = file.dataRows;
    for (var i = 0; i < data.length; i++) {
      final row = data[i];
      String? cell(int? at) => (at != null && at < row.length) ? row[at] : null;
      final date = parseDateWithFormat(cell(dateAt) ?? '', dateFormat);
      if (date == null) {
        errors.add(CsvImportError(i, 'unreadable date'));
        continue;
      }
      final amount = _amountFrom(row, mapping, currency);
      if (amount == null) {
        errors.add(CsvImportError(i, 'unreadable amount'));
        continue;
      }
      final rawDesc = cell(descAt)?.trim();
      final rawNote = cell(noteAt)?.trim();
      final rawCat = cell(catAt)?.trim();
      // e12 §2: rows whose file carries no category get a deterministic
      // merchant suggestion — expenses only, income rows stay untouched.
      final hint = (rawCat == null || rawCat.isEmpty) && !amount.isIncome
          ? CategoryHints.suggest(rawDesc ?? '')
          : null;
      final row2 = CsvPreviewRow(
        rowIndex: i,
        date: date,
        minor: amount.minor,
        isIncome: amount.isIncome,
        description: (rawDesc == null || rawDesc.isEmpty) ? null : rawDesc,
        categoryName: rawCat?.isNotEmpty == true ? rawCat : hint?.$1,
        categoryConfidence: hint?.$2,
        note: (rawNote == null || rawNote.isEmpty) ? null : rawNote,
      );
      rows.add(
        row2.copyWith(
          categoryId: findCat(row2.categoryName, income: row2.isIncome),
          duplicate: existing.contains(
            _dedupKey(row2.date, row2.minor, row2.isIncome),
          ),
        ),
      );
    }
    return CsvPreview(rows: rows, errors: errors, currency: currency);
  }

  ({int minor, bool isIncome})? _amountFrom(
    List<String> row,
    CsvMapping mapping,
    Currency currency,
  ) {
    String? cell(int at) => at < row.length ? row[at] : null;
    final amountAt = mapping.indexOf(ImportRole.amount);
    if (amountAt != null) {
      return parseAmountCell(cell(amountAt) ?? '', currency);
    }
    final debit = mapping.indexOf(ImportRole.debit);
    final credit = mapping.indexOf(ImportRole.credit);
    final debitRaw = debit == null ? null : cell(debit);
    final creditRaw = credit == null ? null : cell(credit);
    // Split-column statement: exactly one side carries the amount. If both
    // or neither do, the row is ambiguous — refuse, never guess.
    final hasDebit = debitRaw != null && debitRaw.trim().isNotEmpty;
    final hasCredit = creditRaw != null && creditRaw.trim().isNotEmpty;
    if (hasDebit == hasCredit) return null;
    if (hasCredit) {
      final v = parseAmountCell(creditRaw, currency);
      if (v == null) return null;
      return (
        minor: v.minor,
        isIncome: mapping.debitMeansExpense ? true : false,
      );
    }
    final v = parseAmountCell(debitRaw!, currency);
    if (v == null) return null;
    return (minor: v.minor, isIncome: !mapping.debitMeansExpense);
  }

  // ---- commit --------------------------------------------------------------

  /// Inserts the user-checked rows in one transaction; duplicates the user
  /// force-included are inserted too (spec: they default off, never silent).
  /// Returns the number of ledger rows written.
  Future<int> commit({
    required int accountId,
    required Currency currency,
    required List<CsvPreviewRow> rows,
    TransactionSource source = TransactionSource.statementImport,
  }) async {
    if (rows.isEmpty) return 0;
    return db.transaction(() async {
      var n = 0;
      for (final r in rows) {
        final txId = await _repo.addTransaction(
          accountId: accountId,
          date: r.date,
          amount: Money(r.minor, currency),
          source: source,
          categoryId: r.categoryId,
          merchant: r.description,
          note: r.note,
          isIncome: r.isIncome,
          externalId: r.externalId,
        );
        // e12 §5: item lines exist only because they reconciled to this
        // row's amount at parse time; keep the document order in position.
        final items = r.items;
        if (items != null && items.isNotEmpty) {
          for (var p = 0; p < items.length; p++) {
            final it = items[p];
            await db
                .into(db.lineItems)
                .insert(
                  LineItemsCompanion.insert(
                    transactionId: txId,
                    position: Value(p),
                    name: it.name,
                    quantity: Value(it.quantity?.toDouble()),
                    unitPriceMinor: Value(it.unitPriceMinor),
                    currencyCode: currency.code,
                  ),
                );
          }
        }
        n++;
      }
      return n;
    });
  }

  // ---- document statements (E11) ---------------------------------------------

  /// Preview for rows parsed out of a photographed/PDF statement
  /// (`StatementLineParser`, e11 §3). Maps 1:1 to [CsvPreviewRow] —
  /// externalId stays null; the duplicate flag is the same date|amount|
  /// direction tuple the CSV/OFX preview uses. Commit rides [commit]
  /// unchanged (source stays `statementImport`).
  Future<CsvPreview> previewStatement({
    required int accountId,
    required Currency currency,
    required List<StatementRow> rows,
  }) async {
    final existing = await _dedupKeys(accountId);
    // e12 §2: scanned rows suggest categories exactly like CSV/OFX rows.
    final cats = await _repo.categories();
    int? findCat(String? name) {
      final t = name?.trim().toLowerCase();
      if (t == null || t.isEmpty) return null;
      for (final c in cats) {
        if (!c.isIncome && c.name.toLowerCase() == t) return c.id;
      }
      return null;
    }

    return CsvPreview(
      rows: [
        for (var i = 0; i < rows.length; i++)
          () {
            final hint = rows[i].isIncome
                ? null
                : CategoryHints.suggest(rows[i].description ?? '');
            return CsvPreviewRow(
              rowIndex: i,
              date: rows[i].date,
              minor: rows[i].minor,
              isIncome: rows[i].isIncome,
              description: rows[i].description,
              categoryId: findCat(hint?.$1),
              categoryName: hint?.$1,
              categoryConfidence: hint?.$2,
              items: rows[i].items,
              duplicate: existing.contains(
                _dedupKey(rows[i].date, rows[i].minor, rows[i].isIncome),
              ),
            );
          }(),
      ],
      errors: const [],
      currency: currency,
    );
  }

  // ---- dedupe ---------------------------------------------------------------

  /// Conservative dedupe key from the spec: (accountId is fixed per
  /// preview, dateDays, amountMinor, isIncome) — nothing fuzzier.
  static String _dedupKey(DateTime date, int minor, bool isIncome) =>
      '${epochDayOf(date)}|$minor|${isIncome ? 1 : 0}';

  Future<Set<String>> _dedupKeys(int accountId) async {
    final rows = await (db.select(
      db.transactions,
    )..where((t) => t.accountId.equals(accountId))).get();
    return {
      for (final t in rows)
        _dedupKey(dateFromEpochDay(t.dateDays), t.amountMinor, t.isIncome),
    };
  }
}
