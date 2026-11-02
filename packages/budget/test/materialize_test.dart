import 'package:budget/budget.dart';
import 'package:test/test.dart';

int d(int y, int m, int day) => dayOf(DateTime.utc(y, m, day));

RecurringRule rule({
  int id = 1,
  String name = 'Rent',
  int amountMinor = 120000,
  BillFrequency frequency = BillFrequency.monthly,
  int? dayOfMonth = 1,
  int? dayOfWeek,
  required int startEpochDay,
  required int nextDueEpochDay,
  bool archived = false,
}) =>
    RecurringRule(
      id: id,
      name: name,
      amountMinor: amountMinor,
      categoryId: 5,
      frequency: frequency,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      startEpochDay: startEpochDay,
      nextDueEpochDay: nextDueEpochDay,
      archived: archived,
    );

void main() {
  group('nextDueAfter', () {
    test('monthly advances one month, one occurrence per call', () {
      final r = rule(
          dayOfMonth: 10,
          startEpochDay: d(2026, 1, 10),
          nextDueEpochDay: d(2026, 11, 10));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2026, 12, 10));
    });

    test('monthly day 31 clamps into short months', () {
      final r = rule(
          dayOfMonth: 31,
          startEpochDay: d(2028, 1, 31),
          nextDueEpochDay: d(2028, 1, 31));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2028, 2, 29)); // leap year
      final r2 = rule(
          dayOfMonth: 31,
          startEpochDay: d(2026, 1, 31),
          nextDueEpochDay: d(2026, 1, 31));
      expect(nextDueAfter(r2, r2.nextDueEpochDay), d(2026, 2, 28));
    });

    test('monthly December wraps the year', () {
      final r =
          rule(startEpochDay: d(2025, 12, 1), nextDueEpochDay: d(2026, 12, 1));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2027, 1, 1));
    });

    test('weekly advances to the same ISO weekday', () {
      // 2026-02-04 is a Wednesday.
      final r = rule(
          frequency: BillFrequency.weekly,
          dayOfMonth: null,
          dayOfWeek: DateTime.wednesday,
          startEpochDay: d(2026, 2, 4),
          nextDueEpochDay: d(2026, 2, 4));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2026, 2, 11));
    });

    test('yearly recurs in the start month, clamping day 29', () {
      final r = rule(
          frequency: BillFrequency.yearly,
          dayOfMonth: 29,
          startEpochDay: d(2024, 2, 29),
          nextDueEpochDay: d(2024, 2, 29));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2025, 2, 28));
    });

    test('yearly December due rolls to next year December', () {
      final r = rule(
          frequency: BillFrequency.yearly,
          dayOfMonth: 15,
          startEpochDay: d(2025, 12, 15),
          nextDueEpochDay: d(2026, 12, 15));
      expect(nextDueAfter(r, r.nextDueEpochDay), d(2027, 12, 15));
    });
  });

  group('planMaterialization', () {
    test('nothing due yields the empty plan', () {
      final plan = planMaterialization(
        rules: [
          rule(startEpochDay: d(2026, 1, 1), nextDueEpochDay: d(2026, 12, 1))
        ],
        todayEpochDay: d(2026, 11, 2),
      );
      expect(plan, same(MaterializationPlan.empty));
    });

    test('overdue rule yields exactly one occurrence, oldest first', () {
      // Two months behind: still a single occurrence per pass (§3.4).
      final r = rule(
          dayOfMonth: 5,
          startEpochDay: d(2026, 1, 5),
          nextDueEpochDay: d(2026, 9, 5));
      final plan = planMaterialization(
        rules: [r],
        todayEpochDay: d(2026, 11, 2),
      );
      expect(plan.due, hasLength(1));
      expect(plan.due.single.dueEpochDay, d(2026, 9, 5)); // backdated
      expect(plan.due.single.nextDueEpochDay, d(2026, 10, 5)); // one hop only
      expect(plan.due.single.name, 'Rent');
      expect(plan.due.single.amountMinor, 120000);
    });

    test('due today materializes', () {
      final r = rule(
          dayOfMonth: 2,
          startEpochDay: d(2026, 1, 2),
          nextDueEpochDay: d(2026, 11, 2));
      final plan = planMaterialization(
        rules: [r],
        todayEpochDay: d(2026, 11, 2),
      );
      expect(plan.due, hasLength(1));
    });

    test('stale rule surfaces paused? instead of inserting', () {
      final r = rule(
          startEpochDay: d(2024, 1, 1),
          nextDueEpochDay: d(2024, 1, 1) + 1); // ~2.5y old
      final plan =
          planMaterialization(rules: [r], todayEpochDay: d(2026, 11, 2));
      expect(plan.due, isEmpty);
      expect(plan.pausedRuleIds, [r.id]);
    });

    test('exactly 365 days late is not yet stale', () {
      final due = d(2025, 11, 2);
      final r = rule(startEpochDay: d(2024, 1, 1), nextDueEpochDay: due);
      final plan = planMaterialization(rules: [r], todayEpochDay: due + 365);
      expect(plan.due, hasLength(1));
      expect(plan.pausedRuleIds, isEmpty);
    });

    test('multiple rules sort by due date, rule id breaks ties', () {
      final a = rule(
          id: 2,
          name: 'B',
          startEpochDay: d(2026, 1, 1),
          nextDueEpochDay: d(2026, 10, 1));
      final b = rule(
          id: 1,
          name: 'A',
          startEpochDay: d(2026, 1, 1),
          nextDueEpochDay: d(2026, 10, 1));
      final c = rule(
          id: 3,
          name: 'C',
          startEpochDay: d(2026, 1, 1),
          nextDueEpochDay: d(2026, 9, 9));
      final plan =
          planMaterialization(rules: [a, b, c], todayEpochDay: d(2026, 11, 2));
      expect(plan.due.map((o) => o.ruleId), [3, 1, 2]);
    });

    test('archived rules never materialize or pause', () {
      final r = rule(
          startEpochDay: d(2024, 1, 1),
          nextDueEpochDay: d(2024, 1, 1),
          archived: true);
      final plan =
          planMaterialization(rules: [r], todayEpochDay: d(2026, 11, 2));
      expect(plan, same(MaterializationPlan.empty));
    });

    test('applying the plan leaves nothing due on a second pass', () {
      var r = rule(
          dayOfMonth: 5,
          startEpochDay: d(2026, 1, 5),
          nextDueEpochDay: d(2026, 10, 5));
      final today = d(2026, 11, 2);
      var plan = planMaterialization(rules: [r], todayEpochDay: today);
      expect(plan.due, hasLength(1));
      r = RecurringRule(
        id: r.id,
        name: r.name,
        amountMinor: r.amountMinor,
        categoryId: r.categoryId,
        frequency: r.frequency,
        dayOfMonth: r.dayOfMonth,
        dayOfWeek: r.dayOfWeek,
        startEpochDay: r.startEpochDay,
        nextDueEpochDay: plan.due.single.nextDueEpochDay, // repo writes it back
        archived: r.archived,
      );
      plan = planMaterialization(rules: [r], todayEpochDay: today);
      expect(plan, same(MaterializationPlan.empty));
    });
  });
}
