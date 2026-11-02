import 'dart:io' show File;

import 'package:core/core.dart' show TransactionSource;
import 'package:drift/drift.dart';
import 'package:drift/native.dart' show NativeDatabase;

import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

/// The whole local store — one SQLite file per device, opened lazily by the
/// app with a path from `path_provider`; tests use [inMemory].
@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Merchants,
    Transactions,
    Budgets,
    LineItems,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Pure-Dart in-memory database (tests, previews).
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  /// The device's persistent store. The app resolves the path through
  /// `path_provider` so this package stays free of Flutter plugins.
  factory AppDatabase.openFile(String path) =>
      AppDatabase(NativeDatabase(File(path)));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // v1 shipped with drift's default createAll; keep that behaviour.
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // #18 (spec §2.4): Manage screen stores an icon key per category.
        // sortOrder already shipped in v1.
        await m.addColumn(categories, categories.icon);
      }
      if (from < 3) {
        // Hardening #23: watchMonth ranges on dateDays alone, which the
        // (accountId, dateDays) index cannot serve — dev installs get the
        // new index exactly as fresh installs do.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS tx_date ON transactions (date_days)',
        );
      }
    },
    // v2: icon key on categories (Manage screen, #18). Line items remain a
    // feature flag — the table shipped in v1 (decision 2), not a migration.
    // v3: tx_date index for the month query (hardening #23).
  );
}
