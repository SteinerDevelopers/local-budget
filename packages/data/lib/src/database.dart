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
  int get schemaVersion => 1;

  // v1 relies on drift's default onCreate (createAll). The first real
  // onUpgrade arrives with v2 — line_items already exists (decision 2), so
  // enabling line items is a feature flag, not a migration.
}
