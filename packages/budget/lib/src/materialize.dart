/// Lazy bill materialization (spec §3.4): the app-open pass, expressed as a
/// pure plan the repository executes. One occurrence per rule per pass,
/// oldest first; stale rules ask "paused?" instead of inserting.
library;

import 'rules.dart';

/// One occurrence to insert: a transaction *as if typed by the user*
/// (source manual, note `Bill: <name>` — spec §3.4). The repository does
/// the insert through the same path QuickAdd uses.
final class BillOccurrence {
  const BillOccurrence({
    required this.ruleId,
    required this.name,
    required this.amountMinor,
    required this.categoryId,
    required this.dueEpochDay,
    required this.nextDueEpochDay,
  });

  final int ruleId;
  final String name;
  final int amountMinor;
  final int categoryId;

  /// The occurrence's own date (the rule's stale `nextDue`) — backdated so
  /// the ledger shows when the bill was actually due.
  final int dueEpochDay;

  /// What `nextDue` becomes after this occurrence materializes.
  final int nextDueEpochDay;
}

/// Outcome of one app-open pass.
final class MaterializationPlan {
  const MaterializationPlan({required this.due, required this.pausedRuleIds});

  static const MaterializationPlan empty =
      MaterializationPlan(due: [], pausedRuleIds: []);

  /// Occurrences to insert, oldest due date first. At most one per rule.
  final List<BillOccurrence> due;

  /// Rules whose due date lags more than [staleAfterDays] — surfaced as a
  /// "paused?" prompt, never silently inserted (spec §3.4).
  final List<int> pausedRuleIds;
}

/// Days beyond which a not-due-in-over-a-year rule is treated as stale.
const int kStaleAfterDays = 365;

/// Plan the app-open pass. [todayEpochDay] is the device's local calendar
/// day; archived rules are skipped.
MaterializationPlan planMaterialization({
  required List<RecurringRule> rules,
  required int todayEpochDay,
  int staleAfterDays = kStaleAfterDays,
}) {
  final due = <BillOccurrence>[];
  final paused = <int>[];
  for (final rule in rules) {
    if (rule.archived || rule.nextDueEpochDay > todayEpochDay) continue;
    if (todayEpochDay - rule.nextDueEpochDay > staleAfterDays) {
      paused.add(rule.id);
      continue;
    }
    due.add(BillOccurrence(
      ruleId: rule.id,
      name: rule.name,
      amountMinor: rule.amountMinor,
      categoryId: rule.categoryId,
      dueEpochDay: rule.nextDueEpochDay,
      nextDueEpochDay: nextDueAfter(rule, rule.nextDueEpochDay),
    ));
  }
  due.sort((a, b) {
    final byDate = a.dueEpochDay.compareTo(b.dueEpochDay);
    return byDate != 0 ? byDate : a.ruleId.compareTo(b.ruleId);
  });
  if (due.isEmpty && paused.isEmpty) return MaterializationPlan.empty;
  return MaterializationPlan(due: due, pausedRuleIds: paused);
}
