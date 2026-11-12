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

  /// E3 §4: 'on' | 'off', absent = off (rollover is opt-in).
  static const settingBudgetRollover = 'budget_rollover';

  /// Epoch-ms of the last materialization pass (B5; §3.4 "one per open").
  static const settingBillsLastMaterializeMs = 'bills_last_materialize_ms';

  static const _periodValues = {'monthly', 'weekly', 'yearly'};

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

  /// Autocomplete candidates (E4 spec §4): case-insensitive prefix match
  /// over merchant names, ranked by usage count desc, then most-recent use
  /// desc, then name asc for determinism. SQLite's LIKE is ASCII-
  /// case-insensitive by default; `%`/`_` in the user's prefix are escaped.
  /// Only merchants attached to at least one transaction can be suggested —
  /// the table gains rows solely through saving transactions anyway.
  Future<List<String>> merchantsLike(String prefix, {int limit = 3}) async {
    final trimmed = prefix.trim();
    if (trimmed.isEmpty) return const [];
    final escaped = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final uses = db.transactions.id.count();
    final lastUsed = db.transactions.dateDays.max();
    final q = db.selectOnly(db.merchants)
      ..join([
        innerJoin(
          db.transactions,
          db.transactions.merchantId.equalsExp(db.merchants.id),
        ),
      ])
      ..addColumns([db.merchants.id, db.merchants.name, uses, lastUsed])
      // escapeChar keeps a literal '%' or '_' typed by the user literal
      // instead of acting as a LIKE wildcard.
      ..where(db.merchants.name.like('$escaped%', escapeChar: r'\'))
      ..groupBy([db.merchants.id])
      ..orderBy([
        OrderingTerm.desc(uses),
        OrderingTerm.desc(lastUsed),
        OrderingTerm.asc(db.merchants.name),
      ])
      ..limit(limit);
    return [for (final row in await q.get()) row.read(db.merchants.name)!];
  }

  /// id → name map over all merchants — the denormalization feed for the
  /// report aggregates (E4 §3). The table only ever holds names minted by
  /// capture/import, so loading it whole is cheap.
  Future<Map<int, String>> merchantNames() async {
    final rows = await db.select(db.merchants).get();
    return {for (final r in rows) r.id: r.name};
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
    int? goalId,
    String? externalId,
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
            goalId: Value(goalId),
            externalId: Value(externalId),
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

  /// Rows in an inclusive `dateDays` window — the multi-period read the E3
  /// budgets sheet runs to feed the engine's rollover chain (weekly/yearly
  /// chains walk months beyond the visible one). Ordered like
  /// [transactionsForMonth]; served by the v3 `tx_date` index.
  Future<List<Transaction>> transactionsInRange(int fromDays, int toDays) =>
      (db.select(db.transactions)
            ..where((t) => t.dateDays.isBetweenValues(fromDays, toDays))
            // §3.5: goal movements are transfers, not income or expense —
            // the engine feed must never see them.
            ..where((t) => t.goalId.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.dateDays),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

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

  /// Insert-or-replace the budget for (category?, period). Null [categoryId] =
  /// overall budget. Handled manually because SQLite treats NULLs as distinct
  /// inside unique indexes. E3: keyed by (category, anchor, periodType).
  Future<void> setBudget({
    int? categoryId,
    required String yearMonth,
    required int limitMinor,
    required String currencyCode,
    String periodType = 'monthly',
    int? rolloverCapMinor,
  }) async {
    monthRange(yearMonth); // validate format before touching the db
    if (!_periodValues.contains(periodType)) {
      throw ArgumentError('unknown periodType: $periodType');
    }
    final existing =
        await (db.select(db.budgets)..where(
              (b) =>
                  b.yearMonth.equals(yearMonth) &
                  b.periodType.equals(periodType) &
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
              periodType: Value(periodType),
              rolloverCapMinor: Value(rolloverCapMinor),
            ),
          );
    } else {
      await (db.update(
        db.budgets,
      )..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(
          limitMinor: Value(limitMinor),
          rolloverCapMinor: Value(rolloverCapMinor),
        ),
      );
    }
  }

  Future<Budget?> budgetFor({
    int? categoryId,
    required String yearMonth,
    String periodType = 'monthly',
  }) =>
      (db.select(db.budgets)..where(
            (b) =>
                b.yearMonth.equals(yearMonth) &
                b.periodType.equals(periodType) &
                (categoryId == null
                    ? b.categoryId.isNull()
                    : b.categoryId.equals(categoryId)),
          ))
          .getSingleOrNull();

  /// Every budget row anchored in a month, all period types — the B3 sheet
  /// maps rows onto engine periods from here.
  Future<List<Budget>> budgetsIn(String yearMonth) => (db.select(
    db.budgets,
  )..where((b) => b.yearMonth.equals(yearMonth))).get();

  /// Budget rows whose `yearMonth` key falls in the inclusive lexicographic
  /// window (`'2024-11' … '2026-11'` — zero-padded, so text order is time
  /// order): the preload the rollover chain's rowFor lookups run against.
  Future<List<Budget>> budgetsBetween(String startYm, String endYm) =>
      (db.select(
        db.budgets,
      )..where((b) => b.yearMonth.isBetweenValues(startYm, endYm))).get();

  Future<void> deleteBudget(int id) =>
      (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();

  // ---- settings -----------------------------------------------------------

  /// e12 §5 — the stored item lines of a committed statement row, in
  /// document order (the transaction detail sheet reads these back).
  Future<List<LineItemRow>> lineItemsFor(int transactionId) =>
      (db.select(db.lineItems)
            ..where((t) => t.transactionId.equals(transactionId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Future<void> setSetting(String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  Future<String?> setting(String key) async => (await (db.select(
    db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  /// Forget one key (e12 §3: the layout-profile reset).
  Future<void> deleteSetting(String key) =>
      (db.delete(db.settings)..where((s) => s.key.equals(key))).go();

  Future<void> setBaseCurrency(String code) async {
    if (Currency.find(code) == null) {
      throw ArgumentError('unknown currency: $code');
    }
    return setSetting(settingBaseCurrency, code);
  }

  Future<String?> baseCurrency() => setting(settingBaseCurrency);

  Future<void> setBudgetRollover(bool enabled) =>
      setSetting(settingBudgetRollover, enabled ? 'on' : 'off');

  Future<bool> budgetRollover() async =>
      await setting(settingBudgetRollover) == 'on';

  Future<void> setBillsLastMaterializeMs(int ms) =>
      setSetting(settingBillsLastMaterializeMs, '$ms');

  Future<int?> billsLastMaterializeMs() async =>
      int.tryParse(await setting(settingBillsLastMaterializeMs) ?? '');

  // ---- recurring rules (E3 §4) ---------------------------------------------

  /// Rules are pure rows — never generated transactions. [dayOfMonth] 1..31
  /// (monthly/yearly, clamped at short months), [dayOfWeek] 1..7 ISO (weekly);
  /// pass the one matching [frequency].
  Future<int> addRule({
    required String name,
    required int amountMinor,
    required String currencyCode,
    required String frequency,
    required DateTime start,
    required DateTime nextDue,
    int? categoryId,
    int? dayOfMonth,
    int? dayOfWeek,
    bool notify = true,
  }) async {
    if (!_periodValues.contains(frequency)) {
      throw ArgumentError('unknown frequency: $frequency');
    }
    if (name.trim().isEmpty) throw ArgumentError('rule name required');
    return db
        .into(db.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            name: name.trim(),
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            categoryId: Value(categoryId),
            frequency: frequency,
            dayOfMonth: Value(dayOfMonth),
            dayOfWeek: Value(dayOfWeek),
            startMs: start.millisecondsSinceEpoch,
            nextDueMs: nextDue.millisecondsSinceEpoch,
            notify: Value(notify),
          ),
        );
  }

  Future<List<RecurringRule>> rules({bool includeArchived = false}) {
    final q = db.select(db.recurringRules)
      ..orderBy([(t) => OrderingTerm.asc(t.nextDueMs)]);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    return q.get();
  }

  /// B5 write-back: advance the cursor (and optionally pause) after planning.
  Future<void> updateRuleDue({
    required int id,
    required DateTime nextDue,
    bool? archived,
  }) => (db.update(db.recurringRules)..where((t) => t.id.equals(id))).write(
    RecurringRulesCompanion(
      nextDueMs: Value(nextDue.millisecondsSinceEpoch),
      archived: archived == null ? const Value.absent() : Value(archived),
    ),
  );

  Future<void> archiveRule(int id, {bool archived = true}) =>
      (db.update(db.recurringRules)..where((t) => t.id.equals(id))).write(
        RecurringRulesCompanion(archived: Value(archived)),
      );

  /// Full rule edit (spec §2.3 "Edit rule"): every editable column in one
  /// write. [dayOfMonth]/[dayOfWeek] follow the new [frequency]; the caller
  /// recomputes [nextDue] — the repository never invents dates.
  Future<void> updateRule({
    required int id,
    required String name,
    required int amountMinor,
    required String frequency,
    required DateTime start,
    required DateTime nextDue,
    int? categoryId,
    int? dayOfMonth,
    int? dayOfWeek,
    bool? notify,
  }) async {
    if (!_periodValues.contains(frequency)) {
      throw ArgumentError('unknown frequency: $frequency');
    }
    if (name.trim().isEmpty) throw ArgumentError('rule name required');
    await (db.update(db.recurringRules)..where((t) => t.id.equals(id))).write(
      RecurringRulesCompanion(
        name: Value(name.trim()),
        amountMinor: Value(amountMinor),
        categoryId: Value(categoryId),
        frequency: Value(frequency),
        dayOfMonth: Value(dayOfMonth),
        dayOfWeek: Value(dayOfWeek),
        startMs: Value(start.millisecondsSinceEpoch),
        nextDueMs: Value(nextDue.millisecondsSinceEpoch),
        notify: notify == null ? const Value.absent() : Value(notify),
      ),
    );
  }

  /// Hard delete — a rule is not money, so nothing cascades (§2.3).
  Future<void> deleteRule(int id) =>
      (db.delete(db.recurringRules)..where((t) => t.id.equals(id))).go();

  // ---- goals (E3 §4) ---------------------------------------------------------

  Future<int> addGoal({
    required String name,
    required String currencyCode,
    int? targetMinor,
    String? icon,
    String? note,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('goal name required');
    return db
        .into(db.goals)
        .insert(
          GoalsCompanion.insert(
            name: name.trim(),
            currencyCode: currencyCode,
            targetMinor: Value(targetMinor),
            icon: Value(icon),
            note: Value(note),
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<Goal>> goals({bool includeArchived = false}) {
    final q = db.select(db.goals)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAtMs)]);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    return q.get();
  }

  /// Column presence follows [Value]: passing nothing leaves a column
  /// alone, `Value(null)` clears it (the editor's blank target = open-
  /// ended), `Value(x)` writes. Plain-nullable args cannot express
  /// "clear", which the editor needs.
  Future<void> updateGoal(
    int id, {
    String? name,
    Value<int?>? targetMinor,
    String? icon,
    Value<String?>? note,
    bool? archived,
  }) => (db.update(db.goals)..where((t) => t.id.equals(id))).write(
    GoalsCompanion(
      name: name == null ? const Value.absent() : Value(name.trim()),
      targetMinor: targetMinor ?? const Value.absent(),
      icon: icon == null ? const Value.absent() : Value(icon),
      note: note ?? const Value.absent(),
      archived: archived == null ? const Value.absent() : Value(archived),
    ),
  );

  /// A goal movement is a [Transactions] row carrying [goalId] — invisible
  /// to the ledger list, the balance strip and budget sums (B6, §3.5),
  /// visible only in the goal detail. [isIncome] is repurposed as the
  /// transfer's direction: false = deposit (money into the goal), true =
  /// withdraw. Either way it is neither income nor expense anywhere else.
  Future<int> addGoalTransfer({
    required int accountId,
    required int goalId,
    required DateTime date,
    required Money amount,
    bool isIncome = false,
    String? note,
    String? baseCurrencyCode,
    double? fxRate,
  }) => addTransaction(
    accountId: accountId,
    date: date,
    amount: amount,
    source: TransactionSource.manual,
    isIncome: isIncome,
    note: note,
    baseCurrencyCode: baseCurrencyCode,
    fxRate: fxRate,
    goalId: goalId,
  );

  /// The goal detail's transfer list, newest first (§2.4). The only read
  /// that surfaces goal-tagged rows.
  Future<List<Transaction>> goalTransfers(int goalId) =>
      (db.select(db.transactions)
            ..where((t) => t.goalId.equals(goalId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.dateDays),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .get();
}

/// A month-list row joined with its category name — the projection the
/// Ledger screen renders (#17); keeps drift row types out of the UI layer.
class LedgerEntryData {
  const LedgerEntryData({
    required this.id,
    required this.day,
    required this.amountMinor,
    required this.currencyCode,
    this.baseAmountMinor,
    this.fxRate,
    required this.isIncome,
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    required this.note,
    this.merchant,
    this.imageRef,
  });

  final int id;
  final DateTime day;
  final int amountMinor;
  final String currencyCode;

  /// FX snapshot in device-base minor units for foreign-currency rows
  /// (null for base-currency rows and for legacy rows without a snapshot).
  /// The month summary must never add raw [amountMinor] across currencies
  /// (hardening #22).
  final int? baseAmountMinor;

  /// The rate that produced [baseAmountMinor] (E5 §6 detail sheet); null
  /// together with a foreign [currencyCode] is the "No rate" state.
  final double? fxRate;
  final bool isIncome;
  final int? categoryId;
  final String? categoryName;

  /// Icon-registry key of the joined category (#18); null ⇒ by-name fallback.
  final String? categoryIcon;
  final String? note;

  /// Name of the merchant joined from [Transaction.merchantId] (#45) —
  /// the payee captured with a scan or import; null on manual rows.
  final String? merchant;

  /// `attachments/<file>` relative path of an original photo stored with
  /// the row (E2 §4); the detail sheet renders it through the store.
  final String? imageRef;
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
    String? baseCurrencyCode,
    double? fxRate,
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
      // E5 §6: entry in a foreign currency snapshots the device base at
      // save time; a null rate still saves the row ("entry never blocks").
      baseCurrencyCode: baseCurrencyCode,
      fxRate: fxRate,
    );
  }

  /// Reactive month list, newest day/entry first (spec §2.1: the saved row
  /// is already visible at the top). Category and merchant names joined in,
  /// so the UI needs no second query (#45: the payee a scan review stores
  /// must be the payee the list shows).
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
            leftOuterJoin(
              db.merchants,
              db.merchants.id.equalsExp(tx.merchantId),
            ),
          ])
          ..where(tx.dateDays.isBetweenValues(r.fromDays, r.toDays))
          // §3.5: goal movements never appear in the ledger list — and the
          // balance strip sums these rows, so it is excluded there too.
          ..where(tx.goalId.isNull())
          ..orderBy([OrderingTerm.desc(tx.dateDays), OrderingTerm.desc(tx.id)]);
    // Bench ruling-B (2026-11-12): the SHEET tail is build-side (FrameTiming
    // split: verge br99=92 ms vs rr99=25 ms at n=460; the same work costs the
    // tablet 25 ms — a CPU-speed ratio, not a GPU one). The dominant cost is
    // this map re-running for the WHOLE month on every write: per row it paid
    // eight readTable lookups and two DateTime rebuilds. One hoisted read and
    // one memoized day conversion; semantics identical.
    final dayMemo = <int, DateTime>{};
    return q.watch().map(
      (rows) => [
        for (final row in rows)
          () {
            final t = row.readTable(tx);  // one lookup, not eight
            return LedgerEntryData(
              id: t.id,
              // Epoch days are calendar days: rebuild local wall-clock so day
              // headers never shift across time zones (negative offsets!).
              // A month spans at most 31 distinct days — memoize the pair.
              day: dayMemo.putIfAbsent(
                t.dateDays,
                () => _localDay(dateFromEpochDay(t.dateDays)),
              ),
              amountMinor: t.amountMinor,
              currencyCode: t.currencyCode,
              baseAmountMinor: t.baseAmountMinor,
              fxRate: t.fxRate,
              isIncome: t.isIncome,
              categoryId: t.categoryId,
              // Outer-joined: null category must not throw.
              categoryName: row.read(db.categories.name),
              categoryIcon: row.read(db.categories.icon),
              // Outer-joined, same rule: a row without a merchant is normal.
              merchant: row.read(db.merchants.name),
              note: t.note,
              imageRef: t.imageRef,
            );
          }(),
      ],
    );
  }

  /// E5 §6: the manual-rate correction for a saved foreign row — either a
  /// "No rate" row (offline at save) or a rate the user wants amended. The
  /// base snapshot is recomputed through core's audited [Money.convertTo]
  /// from the row's stored amount; the same call restamps a row whose rate
  /// was already machine-supplied. Device base resolves at write time, like
  /// every other snapshot path.
  Future<void> setManualRate({required int id, required double fxRate}) async {
    if (!fxRate.isFinite || fxRate <= 0) {
      throw ArgumentError.value(fxRate, 'fxRate', 'must be positive');
    }
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final baseCode = await baseCurrency() ?? 'USD';
    final baseMinor = Money(
      row.amountMinor,
      Currency.resolve(row.currencyCode),
    ).convertTo(Currency.resolve(baseCode), fxRate).minorUnits;
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        fxRate: Value(fxRate),
        baseAmountMinor: Value(baseMinor),
      ),
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
          goalId: Value(row.goalId),
        ),
      );
}
