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

/// Recurring bill rules (spec §2.3, §4). A rule is a *rule*, never a
/// transaction — materialization (materialize.dart) is the only thing that
/// turns one into money, and it does so visibly.
library;

/// Mirrors the drift `recurringRules.frequency` column values. The column is
/// a plain string, so new keys are additive: an older build reads an unknown
/// key through `fromStorage` as `monthly` — it would bill too often, never
/// too rarely (e12 §1).
enum BillFrequency {
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly'),
  quarterly('quarterly'),
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
    case BillFrequency.biweekly:
      // Every 14 days anchored on the rule's start — the occurrence the
      // user reviewed when they saved (e12 §1); day-of-week/month are
      // unused for this kind.
      final start = rule.startEpochDay;
      if (start > fromEpochDay) return start;
      final k = (fromEpochDay + 14 - start) ~/ 14;
      return start + 14 * k;
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
    case BillFrequency.quarterly:
      // Monthly's day-clamp semantics on a 3-month ladder anchored on the
      // start month: Jan→Apr→Jul→Oct from a January start, and a "31st"
      // quarterly bill lands on month end in short months (e12 §1).
      final from = _date(fromEpochDay);
      final anchor = _date(rule.startEpochDay);
      final day = rule.dayOfMonth ?? anchor.day;
      var idx = from.year * 12 + from.month;
      final ladder = idx - (anchor.year * 12 + anchor.month);
      final rem = ladder % 3; // Dart % is non-negative for a positive divisor
      if (rem != 0) idx += 3 - rem;
      var y = (idx - 1) ~/ 12;
      var m = (idx - 1) % 12 + 1;
      var due = _epoch(y, m, clampDay(y, m, day));
      if (due <= fromEpochDay) {
        idx += 3;
        y = (idx - 1) ~/ 12;
        m = (idx - 1) % 12 + 1;
        due = _epoch(y, m, clampDay(y, m, day));
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
