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

  @override
  Set<Column> get primaryKey => {id};
}

/// Monthly budgets. Null [categoryId] = the whole-month overall budget
/// (plan §4 E4 keeps category budgets as the fast-follow).
@TableIndex(
  name: 'budget_month',
  columns: {#categoryId, #yearMonth},
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
