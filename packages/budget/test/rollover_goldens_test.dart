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

// JSON-driven rollover goldens: the fixture doubles as executable
// documentation of spec §3.3 and lives next to the engine like core's
// receipt goldens.
import 'dart:convert';
import 'dart:io';

import 'package:budget/budget.dart';
import 'package:test/test.dart';

void main() {
  test('rollover goldens match the engine', () {
    final raw =
        jsonDecode(File('test/fixtures/rollover_cases.json').readAsStringSync())
            as Map<String, Object?>;
    final cases = raw['cases']! as List<Object?>;
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final kase = c! as Map<String, Object?>;
      final name = kase['name']! as String;
      final months = (kase['months']! as List<Object?>).cast<String>();
      final limits = kase['limits']! as List<Object?>;
      final spent = kase['spent']! as List<Object?>;
      final rows = <String, BudgetRow>{};
      final txs = <EngineTx>[];
      for (var i = 0; i < months.length; i++) {
        final limit = limits[i];
        if (limit != null) {
          rows[months[i]] = BudgetRow(
            categoryId: 42,
            yearMonth: months[i],
            type: BudgetPeriodType.monthly,
            limitMinor: limit as int,
          );
        }
        final s = spent[i]! as int;
        if (s != 0) {
          final parts = months[i].split('-');
          txs.add(EngineTx(
            dateDays: dayOf(
                DateTime.utc(int.parse(parts[0]), int.parse(parts[1]), 10)),
            baseAmountMinor: s,
            categoryId: 42,
          ));
        }
      }
      final lastKey = months.last;
      final parts = lastKey.split('-');
      final period = BudgetPeriod(BudgetPeriodType.monthly,
          DateTime.utc(int.parse(parts[0]), int.parse(parts[1]), 15));
      final status =
          BudgetEngine(rolloverEnabled: kase['rollover']! as bool).statusFor(
        period: period,
        row: rows[lastKey]!,
        rowFor: (p) {
          final anchor = DateTime.utc(1970).add(Duration(days: p.startDay));
          return rows[
              '${anchor.year}-${anchor.month.toString().padLeft(2, '0')}'];
        },
        transactions: txs,
      );
      expect(status.carryMinor, kase['expectCarry'], reason: name);
      expect(status.effectiveLimitMinor, kase['expectEffective'], reason: name);
      expect(status.remainingMinor, kase['expectRemaining'], reason: name);
    }
  });
}
