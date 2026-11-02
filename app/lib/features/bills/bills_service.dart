// #35 — projection of stored bill rules for the Bills tab (design e3 §2.3)
// plus the mark-paid path (§3.4's explicit, immediate sibling of lazy
// materialization). Pure-ish: repository in, view-ready rows out.
import 'package:budget/budget.dart' as bud;
import 'package:core/core.dart' show Currency, Money, TransactionSource;
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';

import 'bill_notifier.dart';

/// A calendar date (local semantics) for an engine epoch day. (`epochDayOf`
/// itself is the data package's helper — one definition, reused here.)
DateTime dayFromEpoch(int epochDay) {
  final u = DateTime.utc(1970).add(Duration(days: epochDay));
  return DateTime(u.year, u.month, u.day);
}

enum BillDueState { overdue, dueSoon, later }

/// §2.3 color rules: overdue → `error`, due within 3 days → bold, else plain.
BillDueState billDueState(int dueEpoch, int todayEpoch) {
  if (dueEpoch < todayEpoch) return BillDueState.overdue;
  return dueEpoch - todayEpoch <= 3 ? BillDueState.dueSoon : BillDueState.later;
}

const List<String> _wdShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _moShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Wed 5 Nov` for an epoch day (spec sample: "Due Wed 5 Nov").
String billDueText(int epochDay) {
  final d = dayFromEpoch(epochDay);
  return '${_wdShort[d.weekday - 1]} ${d.day} ${_moShort[d.month - 1]}';
}

/// `Wed` for an ISO weekday (Mon=1), used by weekly chips and rule text.
String billWeekdayShort(int isoWeekday) => _wdShort[(isoWeekday - 1) % 7];

/// A rule joined with its category and pre-computed due presentation.
final class BillLine {
  const BillLine({
    required this.rule,
    required this.category,
    required this.due,
    required this.dueEpoch,
    required this.state,
    required this.amount,
  });

  final RecurringRule rule;
  final Category? category;
  final DateTime due;
  final int dueEpoch;
  final BillDueState state;
  final Money amount;

  String get dueText => billDueText(dueEpoch);
  bool get isOverdue => state == BillDueState.overdue;
  bool get isDueSoon => state == BillDueState.dueSoon;
}

/// Rules from the repository (already oldest-first — overdue lead the list,
/// §2.3) projected against [now]. Unknown category ids simply render
/// without a chip rather than dropping the bill.
Future<List<BillLine>> loadBillLines(
  LedgerRepository repo, {
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final todayEpoch = epochDayOf(today);
  final rules = await repo.rules();
  if (rules.isEmpty) return const [];
  final cats = {for (final c in await repo.categories()) c.id: c};
  return [
    for (final r in rules)
      BillLine(
        rule: r,
        category: cats[r.categoryId],
        due: dayFromEpoch(r.nextDueMs ~/ 86400000),
        dueEpoch: r.nextDueMs ~/ 86400000,
        state: billDueState(r.nextDueMs ~/ 86400000, todayEpoch),
        amount: Money(r.amountMinor, Currency.resolve(r.currencyCode)),
      ),
  ];
}

/// Engine projection of a stored rule (the engine never sees drift rows).
bud.RecurringRule engineRule(RecurringRule r) => bud.RecurringRule(
  id: r.id,
  name: r.name,
  amountMinor: r.amountMinor,
  categoryId: r.categoryId ?? -1,
  frequency: bud.BillFrequency.fromStorage(r.frequency),
  dayOfMonth: r.dayOfMonth,
  dayOfWeek: r.dayOfWeek,
  startEpochDay: r.startMs ~/ 86400000,
  nextDueEpochDay: r.nextDueMs ~/ 86400000,
  archived: r.archived,
);

/// The first occurrence on or after [start]: [bud.nextDueAfter] is strictly
/// after, so running it from the day before the start answers exactly that.
int firstDueOnOrAfter({
  required bud.BillFrequency frequency,
  int? dayOfMonth,
  int? dayOfWeek,
  required int startEpochDay,
}) => bud.nextDueAfter(
  bud.RecurringRule(
    id: 0,
    name: '',
    amountMinor: 0,
    categoryId: -1,
    frequency: frequency,
    dayOfMonth: dayOfMonth,
    dayOfWeek: dayOfWeek,
    startEpochDay: startEpochDay,
    nextDueEpochDay: startEpochDay,
  ),
  startEpochDay - 1,
);

/// Mark paid (§3.4): one real transaction *as if typed by the user* through
/// the exact QuickAdd repository path, back-dated to the occurrence's own
/// day, then the rule's cursor advances and the reminder re-schedules.
/// Returns the day the payment landed on.
Future<DateTime> markBillPaid(
  LedgerRepository repo,
  BillLine line, {
  bool reschedule = true,
}) async {
  final r = line.rule;
  final acc = await repo.defaultAccount();
  await repo.addTransaction(
    accountId: acc.id,
    date: line.due,
    amount: line.amount,
    source: TransactionSource.manual,
    categoryId: r.categoryId,
    note: 'Bill: ${r.name}',
  );
  final nextEpoch = bud.nextDueAfter(engineRule(r), line.dueEpoch);
  await repo.updateRuleDue(id: r.id, nextDue: dayFromEpoch(nextEpoch));
  if (reschedule && r.notify) {
    // Inert until the app shell bootstraps BillNotifier — tests never
    // reach a method channel.
    await BillNotifier.schedule(
      ruleId: r.id,
      name: r.name,
      due: dayFromEpoch(nextEpoch),
    );
  }
  return line.due;
}
