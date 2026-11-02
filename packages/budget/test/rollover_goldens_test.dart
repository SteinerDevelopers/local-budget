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
