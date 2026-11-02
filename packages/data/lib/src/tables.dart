import 'package:drift/drift.dart';

import 'converters.dart';

/// Schema v1 (plan §5, decision 2). Money is always integer minor units plus
/// an ISO 4217 code — never doubles. `lineItems` is **reserved** in v1: the
/// table ships and is tested, but nothing writes to it before v2.
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtMs => integer()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Nullable self reference — one level of nesting is enough for v1.
  IntColumn get parentId => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Optional UI tint (ARGB int); semantics stay UI-side.
  IntColumn get colorHint => integer().nullable()();

  /// Key into the app's icon registry (#18, spec §2.4); null ⇒ the UI falls
  /// back to its by-name mapping, so old rows keep rendering.
  TextColumn get icon => text().nullable()();

  /// True = income category (QuickAdd shows it under the Income toggle).
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();
}

class Merchants extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

/// Hardening #23: the ledger month page ranges on [dateDays] with no
/// accountId predicate, so it needs a leading-column index of its own —
/// [tx_account_date] cannot serve it.
@TableIndex(name: 'tx_date', columns: {#dateDays})
@TableIndex(name: 'tx_account_date', columns: {#accountId, #dateDays})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get merchantId => integer().nullable().references(Merchants, #id)();

  /// Epoch days (UTC midnight) — timezone-proof calendar arithmetic.
  IntColumn get dateDays => integer()();

  /// Amount exactly as recorded on the bill/receipt/statement.
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();

  /// FX snapshot at entry time (decision 6: base currency is per device).
  /// Populated only when [currencyCode] differs from the device base then.
  IntColumn get baseAmountMinor => integer().nullable()();
  RealColumn get fxRate => real().nullable()();

  TextColumn get note => text().nullable()();

  /// App-private relative path of the kept original image/PDF (E2/E3).
  TextColumn get imageRef => text().nullable()();

  /// How the row entered the ledger (feasibility §5 discriminator).
  TextColumn get source => text().map(const TransactionSourceConverter())();

  /// E1 §2.1: expense vs income — amountMinor stays unsigned, the sign
  /// lives in the display layer (spec §3).
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();

  /// E3 §3.5: non-null ⇒ this row is a goal transfer, not a ledger entry —
  /// hidden from ledger, balance strip and budget sums (B6 renders the
  /// exclusion; the schema encodes it from day one).
  IntColumn get goalId => integer().nullable().references(Goals, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

/// E3 §4: savings goals. Money is again minor units + code; [targetMinor]
/// null = open-ended goal (progress bar degrades to a plain total).
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get targetMinor => integer().nullable()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();

  /// Key into the app's icon registry, same convention as [Categories.icon].
  TextColumn get icon => text().nullable()();

  /// §2.4 editor note ("Editor: name, optional target amount, note").
  /// Arrives as a v5 ADD COLUMN — v4 created this table before B6's editor.
  TextColumn get note => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtMs => integer()();
}

/// E3 §4: recurring bill/goal-contribution rules. Rows are **rules**, never
/// generated transactions — materialization (B5) inserts at most one missed
/// occurrence per app-open. [frequency]/day columns mirror the budget
/// package's `BillFrequency` storage keys; kept as plain TEXT here so this
/// package stays independent of `budget`.
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();

  /// 'weekly' | 'monthly' | 'yearly'.
  TextColumn get frequency => text()();

  /// 1..31 for monthly/yearly (clamped at short months), 1..7 ISO dow for
  /// weekly; the unused partner column stays null.
  IntColumn get dayOfMonth => integer().nullable()();
  IntColumn get dayOfWeek => integer().nullable()();

  IntColumn get startMs => integer()();

  /// Advance-once cursor B5 advances when it materializes; a row far in the
  /// past signals a stale rule (pause instead of insert, §3.4).
  IntColumn get nextDueMs => integer()();

  BoolColumn get notify => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Budgets per (category?, period). Null [categoryId] = the whole-month
/// overall budget (plan §4 E4 keeps category budgets as the fast-follow).
/// E3 §4: one row per **period**, not per calendar month — weekly/yearly
/// share the [yearMonth] key as the period's anchor label (budget package
/// `BudgetPeriodType.keyFor`).
@TableIndex(
  name: 'budget_month_period',
  columns: {#categoryId, #yearMonth, #periodType},
  unique: true,
)
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();

  /// ISO calendar month, `2026-11`. String keys survive reporting forever.
  TextColumn get yearMonth => text().withLength(min: 7, max: 7)();
  IntColumn get limitMinor => integer()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();

  /// 'monthly' | 'weekly' | 'yearly' — budget package storage keys.
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();

  /// Per-row rollover cap override; null = engine default (2× limit, §3.3).
  /// No UI in v1 — schema room for the "cap carry" ask.
  IntColumn get rolloverCapMinor => integer().nullable()();
}

/// Reserved (decision 2): ships in v1 so enabling line-item OCR later is an
/// additive feature, not a migration. Nothing in v1 writes here.
@DataClassName('LineItemRow')
class LineItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().references(Transactions, #id)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get name => text()();
  RealColumn get quantity => real().nullable()();
  IntColumn get unitPriceMinor => integer().nullable()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
}

/// Device-scoped key/value store (base currency, review-sheet defaults…).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
