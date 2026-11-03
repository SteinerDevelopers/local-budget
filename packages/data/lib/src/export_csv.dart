import 'package:core/core.dart' show Currency;
import 'package:drift/drift.dart';

import 'csv_codec.dart';
import 'database.dart';
import 'integrity.dart';
import 'ledger_repository.dart' show dateFromEpochDay;

/// E5 spec §2 — CSV export builder (free, lossless-enough, re-importable).
///
/// Header is fixed and lowercase; amounts are **signed decimal** in the
/// row's own currency (expenses negative, income positive — the bank
/// convention, so the import wizard (§4) reads our own files back).
/// Goal transfers are not ledger entries (E3 §3.5) and stay out.
class CsvExport {
  CsvExport(this.db);

  final AppDatabase db;

  static const List<String> header = [
    'date',
    'description',
    'category',
    'note',
    'amount',
    'currency',
    'account',
  ];

  static const _dateFormat = _IsoDate();

  /// Share-sheet friendly file name (spec §2).
  static String fileName(DateTime now) =>
      'budget-export-${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}.csv';

  Future<String> build({int? accountId}) async {
    // §7: snapshot consistency — flush WAL first (no-op on rollback).
    await DbIntegrity.walCheckpoint(db);
    Expression<bool> cond = db.transactions.goalId.isNull();
    if (accountId != null) {
      cond = cond & db.transactions.accountId.equals(accountId);
    }
    final rows =
        await (db.select(db.transactions).join([
                leftOuterJoin(
                  db.accounts,
                  db.accounts.id.equalsExp(db.transactions.accountId),
                ),
                leftOuterJoin(
                  db.merchants,
                  db.merchants.id.equalsExp(db.transactions.merchantId),
                ),
                leftOuterJoin(
                  db.categories,
                  db.categories.id.equalsExp(db.transactions.categoryId),
                ),
              ])
              ..where(cond)
              ..orderBy([
                OrderingTerm.asc(db.transactions.dateDays),
                OrderingTerm.asc(db.transactions.id),
              ]))
            .get();

    final out = <List<String>>[header];
    for (final row in rows) {
      final t = row.readTable(db.transactions);
      final merchant = row.readTableOrNull(db.merchants)?.name;
      final note = t.note ?? '';
      out.add([
        _dateFormat.format(dateFromEpochDay(t.dateDays)),
        (merchant != null && merchant.isNotEmpty) ? merchant : note,
        row.readTableOrNull(db.categories)?.name ?? '',
        note,
        _signedDecimal(t.amountMinor, t.isIncome, t.currencyCode),
        t.currencyCode,
        row.readTableOrNull(db.accounts)?.name ?? '',
      ]);
    }
    return encodeCsv(out);
  }

  /// Unsigned storage + isIncome flag → signed dot-decimal, no grouping,
  /// no locale: exactly what [parseAmount]-style importers expect.
  static String _signedDecimal(int minor, bool isIncome, String code) {
    final cur = Currency.resolve(code);
    final abs = minor.abs();
    final String mag;
    if (cur.minorUnits == 0) {
      mag = '$abs';
    } else {
      final frac = (abs % cur.pow10).toString().padLeft(cur.minorUnits, '0');
      mag = '${abs ~/ cur.pow10}.$frac';
    }
    if (isIncome) return mag;
    return minor == 0 ? '0' : '-$mag';
  }
}

/// Tiny private date formatter — the data package stays Flutter-free.
class _IsoDate {
  const _IsoDate();
  String format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
