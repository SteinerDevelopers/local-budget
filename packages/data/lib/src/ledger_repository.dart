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

/// A UTC calendar day read back as a local calendar day — same Y/M/D at
/// local midnight, so ledger day headers never shift a day west/east of UTC.
DateTime _localDay(DateTime utcDay) =>
    DateTime(utcDay.year, utcDay.month, utcDay.day);

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
    bool isIncome = false,
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
            isIncome: Value(isIncome),
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

/// A month-list row joined with its category name — the projection the
/// Ledger screen renders (#17); keeps drift row types out of the UI layer.
class LedgerEntryData {
  const LedgerEntryData({
    required this.id,
    required this.day,
    required this.amountMinor,
    required this.currencyCode,
    required this.isIncome,
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    required this.note,
  });

  final int id;
  final DateTime day;
  final int amountMinor;
  final String currencyCode;
  final bool isIncome;
  final int? categoryId;
  final String? categoryName;

  /// Icon-registry key of the joined category (#18); null ⇒ by-name fallback.
  final String? categoryIcon;
  final String? note;
}

// ---- E1 ledger (design §2.1) ------------------------------------------------

extension LedgerE1 on LedgerRepository {
  /// The single implicit account E1 needs; created by [ensureDefaults].
  Future<Account> defaultAccount() async {
    final list = await accounts();
    if (list.isNotEmpty) return list.first;
    final base = await baseCurrency() ?? 'USD';
    await createAccount(name: 'Cash', currencyCode: base);
    return (await accounts()).first;
  }

  /// Seed name → icon-registry key, first-launch order (§2.4). The app owns
  /// the key → [IconData] mapping; the db only stores the key string.
  static const defaultExpenseCategories = <String, String>{
    'Food': 'restaurant_outlined',
    'Housing': 'home_outlined',
    'Transport': 'directions_bus_outlined',
    'Utilities': 'bolt_outlined',
    'Fun': 'movie_outlined',
    'Health': 'monitor_heart_outlined',
    'Other': 'label_outline',
  };
  static const defaultIncomeCategories = <String, String>{
    'Salary': 'payments_outlined',
    'Other income': 'trending_up',
  };

  /// Idempotent first-launch seeding: default account + category list.
  Future<void> ensureDefaults() async {
    await defaultAccount();
    if ((await categories()).isNotEmpty) return;
    var sort = 0;
    for (final MapEntry(:key, :value) in defaultExpenseCategories.entries) {
      await addCategory(key, icon: value, sortOrder: sort++);
    }
    for (final MapEntry(:key, :value) in defaultIncomeCategories.entries) {
      await addCategory(key, icon: value, sortOrder: sort++, isIncome: true);
    }
  }

  Future<int> addCategory(
    String name, {
    String? icon,
    int sortOrder = 0,
    bool isIncome = false,
  }) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          name: name,
          icon: Value(icon),
          sortOrder: Value(sortOrder),
          isIncome: Value(isIncome),
        ),
      );

  /// Partial update for the Manage rename sheet (#18, spec §2.4).
  Future<void> updateCategory(int id, {String? name, String? icon}) async {
    await (db.update(db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        icon: icon == null ? const Value.absent() : Value(icon),
      ),
    );
  }

  /// Persists one section's new drag order (§2.4): sortOrder = list index.
  Future<void> reorderCategories({
    required bool income,
    required List<int> orderedIds,
  }) => db.transaction(() async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (db.update(db.categories)..where((t) => t.id.equals(orderedIds[i])))
          .write(CategoriesCompanion(sortOrder: Value(i)));
    }
  });

  Future<List<Category>> categories({bool? income}) {
    final q = db.select(db.categories)
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    if (income != null) q.where((t) => t.isIncome.equals(income));
    return q.get();
  }

  Stream<List<Category>> watchCategories() => (db.select(
    db.categories,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();

  /// One QuickAdd insert: unsigned amount + explicit kind (§3 sign rule —
  /// the row stores magnitude, the label carries the sign).
  Future<int> addEntry({
    required DateTime date,
    required Money amount,
    required bool isIncome,
    required int categoryId,
    String? note,
  }) async {
    if (amount.isNegative) {
      throw ArgumentError('ledger amounts are unsigned; kind carries the sign');
    }
    final account = await defaultAccount();
    return addTransaction(
      accountId: account.id,
      date: date,
      amount: amount,
      source: TransactionSource.manual,
      categoryId: categoryId,
      note: note,
      isIncome: isIncome,
    );
  }

  /// Reactive month list, newest day/entry first (spec §2.1: the saved row
  /// is already visible at the top). Category name joined in, so the UI
  /// needs no second query.
  Stream<List<LedgerEntryData>> watchMonth(String yearMonth) {
    final r = monthRange(yearMonth);
    final tx = db.transactions;
    // JoinedSelectStatement takes plain expressions (no row-typed callbacks).
    final q =
        db.select(tx).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(tx.categoryId),
            ),
          ])
          ..where(tx.dateDays.isBetweenValues(r.fromDays, r.toDays))
          ..orderBy([OrderingTerm.desc(tx.dateDays), OrderingTerm.desc(tx.id)]);
    return q.watch().map(
      (rows) => [
        for (final row in rows)
          LedgerEntryData(
            id: row.readTable(tx).id,
            // Epoch days are calendar days: rebuild local wall-clock so day
            // headers never shift across time zones (negative offsets!).
            day: _localDay(dateFromEpochDay(row.readTable(tx).dateDays)),
            amountMinor: row.readTable(tx).amountMinor,
            currencyCode: row.readTable(tx).currencyCode,
            isIncome: row.readTable(tx).isIncome,
            categoryId: row.readTable(tx).categoryId,
            // Outer-joined: null category must not throw.
            categoryName: row.read(db.categories.name),
            categoryIcon: row.read(db.categories.icon),
            note: row.readTable(tx).note,
          ),
      ],
    );
  }

  /// Fetch-then-delete so a SnackBar Undo (§2.1, zero dialogs) can re-insert
  /// the exact row.
  Future<Transaction?> deleteEntry(int id) async {
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> restoreEntry(Transaction row) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          id: Value(row.id), // Undo reuses the exact row id (§2.1).
          accountId: row.accountId,
          dateDays: row.dateDays,
          amountMinor: row.amountMinor,
          currencyCode: row.currencyCode,
          source: row.source,
          categoryId: Value(row.categoryId),
          merchantId: Value(row.merchantId),
          note: Value(row.note),
          imageRef: Value(row.imageRef),
          baseAmountMinor: Value(row.baseAmountMinor),
          fxRate: Value(row.fxRate),
          isIncome: Value(row.isIncome),
        ),
      );
}
