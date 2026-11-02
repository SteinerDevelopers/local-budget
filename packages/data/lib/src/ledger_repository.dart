import 'package:core/core.dart';
import 'package:drift/drift.dart';

import 'database.dart';

/// Calendar helpers — dates are stored as epoch days (UTC midnight) so month
/// math never drifts with device timezones.
int epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

DateTime dateFromEpochDay(int days) => DateTime.fromMillisecondsSinceEpoch(
  days * Duration.millisecondsPerDay,
  isUtc: true,
);

/// `2026-11` -> inclusive epoch-day bounds of that calendar month.
({int fromDays, int toDays}) monthRange(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length != 2 ||
      parts[0].length != 4 ||
      parts[1].length != 2 ||
      int.tryParse(parts[0]) == null ||
      int.tryParse(parts[1]) == null) {
    throw ArgumentError('yearMonth must look like 2026-11, got: $yearMonth');
  }
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  if (m < 1 || m > 12) throw ArgumentError('bad month in $yearMonth');
  final start = DateTime.utc(y, m);
  final end = DateTime.utc(y, m + 1).subtract(const Duration(days: 1));
  return (fromDays: epochDayOf(start), toDays: epochDayOf(end));
}

String yearMonthOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Thin, typed gateway over the schema — the only write path the app uses.
class LedgerRepository {
  LedgerRepository(this.db);

  final AppDatabase db;

  static const settingBaseCurrency = 'base_currency';

  // ---- accounts -----------------------------------------------------------

  Future<int> createAccount({
    required String name,
    required String currencyCode,
  }) async {
    if (Currency.find(currencyCode) == null) {
      throw ArgumentError('unknown currency: $currencyCode');
    }
    return db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            currencyCode: currencyCode,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<Account>> accounts({bool includeArchived = false}) {
    final q = db.select(db.accounts)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAtMs)]);
    if (!includeArchived) q.where((t) => t.isArchived.equals(false));
    return q.get();
  }

  // ---- merchants ----------------------------------------------------------

  Future<int> findOrCreateMerchant(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('merchant name required');
    final existing = await (db.select(
      db.merchants,
    )..where((m) => m.name.equals(trimmed))).getSingleOrNull();
    if (existing != null) return existing.id;
    return db
        .into(db.merchants)
        .insert(MerchantsCompanion.insert(name: trimmed));
  }

  // ---- transactions -------------------------------------------------------

  /// Inserts one reviewed header. When [baseCurrencyCode] differs from the
  /// amount's currency and an [fxRate] is supplied, the FX snapshot columns
  /// are filled through core's audited [Money.convertTo] — never re-parsed.
  Future<int> addTransaction({
    required int accountId,
    required DateTime date,
    required Money amount,
    required TransactionSource source,
    int? categoryId,
    String? merchant,
    String? note,
    String? imageRef,
    String? baseCurrencyCode,
    double? fxRate,
  }) async {
    int? merchantId;
    if (merchant != null && merchant.trim().isNotEmpty) {
      merchantId = await findOrCreateMerchant(merchant);
    }
    int? baseMinor;
    double? rate;
    if (baseCurrencyCode != null &&
        fxRate != null &&
        baseCurrencyCode != amount.currency.code) {
      baseMinor = amount
          .convertTo(Currency.resolve(baseCurrencyCode), fxRate)
          .minorUnits;
      rate = fxRate;
    }
    return db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: accountId,
            dateDays: epochDayOf(date),
            amountMinor: amount.minorUnits,
            currencyCode: amount.currency.code,
            source: source,
            categoryId: Value(categoryId),
            merchantId: Value(merchantId),
            note: Value(note),
            imageRef: Value(imageRef),
            baseAmountMinor: Value(baseMinor),
            fxRate: Value(rate),
          ),
        );
  }

  Future<List<Transaction>> transactionsForMonth(
    String yearMonth, {
    int? accountId,
  }) {
    final r = monthRange(yearMonth);
    final q = db.select(db.transactions)
      ..where((t) => t.dateDays.isBetweenValues(r.fromDays, r.toDays))
      ..orderBy([
        (t) => OrderingTerm.asc(t.dateDays),
        (t) => OrderingTerm.asc(t.id),
      ]);
    if (accountId != null) q.where((t) => t.accountId.equals(accountId));
    return q.get();
  }

  /// Spend (positive amounts) for a month, in one currency — refunds (negative
  /// amounts) reduce the total. Returns minor units.
  Future<int> monthSpendMinor({
    required String yearMonth,
    required String currencyCode,
    int? accountId,
    int? categoryId,
  }) async {
    final rows = await transactionsForMonth(yearMonth, accountId: accountId);
    var sum = 0;
    for (final t in rows) {
      if (t.currencyCode != currencyCode) continue;
      if (categoryId != null && t.categoryId != categoryId) continue;
      sum += t.amountMinor;
    }
    return sum;
  }

  /// Total across *all* currencies using the FX snapshot taken at entry time
  /// (rows already in the base currency count at face value).
  Future<int> monthSpendBaseMinor({
    required String yearMonth,
    required String baseCurrencyCode,
  }) async {
    final rows = await transactionsForMonth(yearMonth);
    var sum = 0;
    for (final t in rows) {
      sum += t.currencyCode == baseCurrencyCode
          ? t.amountMinor
          : (t.baseAmountMinor ??
                (throw StateError(
                  'transaction ${t.id} in ${t.currencyCode} lacks an fx snapshot',
                )));
    }
    return sum;
  }

  // ---- budgets ------------------------------------------------------------

  /// Insert-or-replace the budget for (category?, month). Null [categoryId] =
  /// overall budget. Handled manually because SQLite treats NULLs as distinct
  /// inside unique indexes.
  Future<void> setBudget({
    int? categoryId,
    required String yearMonth,
    required int limitMinor,
    required String currencyCode,
  }) async {
    monthRange(yearMonth); // validate format before touching the db
    final existing =
        await (db.select(db.budgets)..where(
              (b) =>
                  b.yearMonth.equals(yearMonth) &
                  (categoryId == null
                      ? b.categoryId.isNull()
                      : b.categoryId.equals(categoryId)),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: Value(categoryId),
              yearMonth: yearMonth,
              limitMinor: limitMinor,
              currencyCode: currencyCode,
            ),
          );
    } else {
      await (db.update(db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(limitMinor: Value(limitMinor)));
    }
  }

  Future<Budget?> budgetFor({int? categoryId, required String yearMonth}) =>
      (db.select(db.budgets)..where(
            (b) =>
                b.yearMonth.equals(yearMonth) &
                (categoryId == null
                    ? b.categoryId.isNull()
                    : b.categoryId.equals(categoryId)),
          ))
          .getSingleOrNull();

  // ---- settings -----------------------------------------------------------

  Future<void> setSetting(String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Future<String?> setting(String key) async => (await (db.select(
    db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setBaseCurrency(String code) async {
    if (Currency.find(code) == null) {
      throw ArgumentError('unknown currency: $code');
    }
    return setSetting(settingBaseCurrency, code);
  }

  Future<String?> baseCurrency() => setting(settingBaseCurrency);
}
