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

import 'dart:ffi';
import 'dart:io';

import 'package:data/data.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:test/test.dart';

/// v4 created `goals` before the B6 editor promised a note (§2.4); shipped
/// v4 installs therefore lack the column. This test rewinds a current
/// database to the exact v4 shape (drop the column, pin user_version = 4)
/// and verifies the open upgrades it back — re-runnable via the same
/// PRAGMA table_info guard the from<4 steps use.
void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('budget_mig_v5');
    path = '${tmp.path}/ledger.sqlite';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a shipped v4 install gains goals.note and keeps its rows', () async {
    // A current install with real data...
    final db1 = AppDatabase.openFile(path);
    final repo1 = LedgerRepository(db1);
    final goalId = await repo1.addGoal(
      name: 'Emergency',
      currencyCode: 'USD',
      targetMinor: 500000,
    );
    await repo1.addGoal(
      name: 'Camera',
      currencyCode: 'USD',
      targetMinor: null,
      note: 'old note', // will vanish with the column
    );
    await db1.close();

    // ...rewound to the shipped v4 shape: no goals.note, version pinned.
    final raw = raw_sqlite3.sqlite3.open(path);
    raw.execute('ALTER TABLE goals DROP COLUMN note');
    raw.execute('PRAGMA user_version = 4');
    raw.dispose();

    final db2 = AppDatabase.openFile(path);
    final repo2 = LedgerRepository(db2);
    addTearDown(db2.close);

    expect(
      (await db2.customSelect('PRAGMA user_version').getSingle())
          .data['user_version'],
      // Upgrades run to the live schemaVersion (v6 rides along).
      6,
    );
    final cols = await db2.customSelect("PRAGMA table_info('goals')").get();
    expect(cols.map((r) => r.data['name']), contains('note'));

    final rows = await repo2.goals();
    expect(rows, hasLength(2));
    final emergency = rows.firstWhere((g) => g.id == goalId);
    expect(emergency.name, 'Emergency');
    expect(emergency.targetMinor, 500000);
    expect(emergency.note, isNull); // added NULL for pre-B6 rows

    // The editor's write path works on upgraded databases.
    await repo2.updateGoal(goalId, note: const Value('three months of rent'));
    expect(
      (await repo2.goals()).firstWhere((g) => g.id == goalId).note,
      'three months of rent',
    );
  });
}
