/// Recurring bill rules (spec §2.3, §4). A rule is a *rule*, never a
/// transaction — materialization (materialize.dart) is the only thing that
/// turns one into money, and it does so visibly.
library;

/// Mirrors the drift `recurringRules.frequency` column values.
enum BillFrequency {
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const BillFrequency(this.storageKey);

  final String storageKey;

  static BillFrequency fromStorage(String value) => BillFrequency.values
      .firstWhere((f) => f.storageKey == value, orElse: () => monthly);
}

/// A stored bill rule projected for the engine. A day-of-month of 29–31
/// clamps to the last day of shorter months (a user who picks "the 31st"
/// means month end when the 31st doesn't exist); a yearly rule recurs in
/// the month of its [startEpochDay].
final class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.categoryId,
    required this.frequency,
    this.dayOfMonth,
    this.dayOfWeek,
    required this.startEpochDay,
    required this.nextDueEpochDay,
    this.archived = false,
  });

  final int id;
  final String name;
  final int amountMinor;
  final int categoryId;
  final BillFrequency frequency;

  /// Monthly/yearly rules.
  final int? dayOfMonth;

  /// Weekly rules — ISO weekday (Mon=1..Sun=7).
  final int? dayOfWeek;

  final int startEpochDay;
  final int nextDueEpochDay;
  final bool archived;
}

DateTime _date(int epochDay) =>
    DateTime.utc(1970).add(Duration(days: epochDay));

int _epoch(int year, int month, int day) =>
    DateTime.utc(year, month, day).difference(DateTime.utc(1970)).inDays;

/// Clamp a day-of-month into a (year, month) that may be shorter.
int clampDay(int year, int month, int day) {
  final lastDay = DateTime.utc(year, month + 1)
      .difference(DateTime.utc(year, month))
      .inDays;
  return day > lastDay ? lastDay : day;
}

/// The next due epoch day strictly after [fromEpochDay] — called once per
/// materialized occurrence (spec §3.4: exactly one per app-open).
int nextDueAfter(RecurringRule rule, int fromEpochDay) {
  switch (rule.frequency) {
    case BillFrequency.weekly:
      final target = rule.dayOfWeek ?? DateTime.monday;
      final d = _date(fromEpochDay + 1);
      return fromEpochDay + 1 + (target - d.weekday + 7) % 7;
    case BillFrequency.monthly:
      final from = _date(fromEpochDay);
      final day = rule.dayOfMonth ?? 1;
      var due =
          _epoch(from.year, from.month, clampDay(from.year, from.month, day));
      if (due <= fromEpochDay) {
        final ny = from.month == 12 ? from.year + 1 : from.year;
        final nm = from.month == 12 ? 1 : from.month + 1;
        due = _epoch(ny, nm, clampDay(ny, nm, day));
      }
      return due;
    case BillFrequency.yearly:
      final from = _date(fromEpochDay);
      final anchor = _date(rule.startEpochDay);
      final day = rule.dayOfMonth ?? anchor.day;
      var due = _epoch(
          from.year, anchor.month, clampDay(from.year, anchor.month, day));
      if (due <= fromEpochDay) {
        due = _epoch(from.year + 1, anchor.month,
            clampDay(from.year + 1, anchor.month, day));
      }
      return due;
  }
}
