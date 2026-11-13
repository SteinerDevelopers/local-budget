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
    Goals,
    RecurringRules,
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
  int get schemaVersion => 6;

  /// E5 §5 — drift cannot express partial indexes, so neither onCreate nor
  /// the v6 upgrade step can go through the table classes; one shared
  /// statement keeps the fresh-install and upgraded shapes identical.
  static const _createExternalIndex =
      'CREATE UNIQUE INDEX IF NOT EXISTS tx_account_external '
      'ON transactions (account_id, external_id) '
      'WHERE external_id IS NOT NULL';

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // v1 shipped with drift's default createAll; keep that behaviour —
    // plus the raw partial index fresh installs would otherwise miss.
    onCreate: (m) async {
      await m.createAll();
      await customStatement(_createExternalIndex);
    },
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
      if (from < 4) {
        // E3 §4 ("schema v2" in the design doc; drift v4): goals first so the
        // transactions.goal_id FK target exists, then rules, then the new
        // budget columns, then swap the month-unique index for the
        // period-unique one. Existing rows default to 'monthly' — identical
        // semantics to v3.
        await m.createTable(goals);
        await m.createTable(recurringRules);
        await _addColumnIfAbsent(m, budgets, budgets.periodType);
        await _addColumnIfAbsent(m, budgets, budgets.rolloverCapMinor);
        await _addColumnIfAbsent(m, transactions, transactions.goalId);
        await customStatement('DROP INDEX IF EXISTS budget_month');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS budget_month_period '
          'ON budgets (category_id, year_month, period_type)',
        );
      }
      if (from < 5) {
        // B6 (spec §2.4 editor): goals gained a note. Upgrades below 4
        // create the table with the column already present, so re-running
        // through here is safe via the same table_info check as v4.
        await _addColumnIfAbsent(m, goals, goals.note);
      }
      if (from < 6) {
        // E5 §5: OFX FITID for idempotent statement re-imports. Partial
        // unique index is raw SQL by necessity; the table_info guard keeps
        // the step re-runnable like v5's.
        await _addColumnIfAbsent(m, transactions, transactions.externalId);
        await customStatement(_createExternalIndex);
      }
    },
    // v2: icon key on categories (Manage screen, #18). Line items remain a
    // feature flag — the table shipped in v1 (decision 2), not a migration.
    // v3: tx_date index for the month query (hardening #23).
    // v4: E3 — Goals, RecurringRules, budget periodType/rolloverCapMinor,
    //     transactions.goalId, budget_month → budget_month_period (#33).
    // v5: goals.note for the B6 goals editor (#37).
    // v6: transactions.externalId + tx_account_external partial index —
    //     OFX FITID dedupe (E5 §5).
  );

  /// SQLite has no `ADD COLUMN IF NOT EXISTS`, and the from<4 step re-runs
  /// over databases that already carry the column (the schema-rewind case
  /// perf_regression_test pins). Check table_info first; skipping an existing
  /// column keeps the whole step re-runnable, matching v3's IF NOT EXISTS.
  Future<void> _addColumnIfAbsent(
    Migrator m,
    TableInfo table,
    GeneratedColumn<Object> column,
  ) async {
    final present = await customSelect(
      "PRAGMA table_info('${table.actualTableName}')",
    ).get();
    if (present.every((row) => row.data['name'] != column.name)) {
      await m.addColumn(table, column);
    }
  }
}
