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

/// Statement-import dedupe (decision 3: CSV + OFX import in v1, free).
///
/// Policy is deliberately *conservative*: an exact key match is required to
/// auto-flag a duplicate; near-matches are surfaced for the user to decide in
/// the import preview (feasibility §3.3 — never silently drop a transaction).
class DedupeKey {
  const DedupeKey({
    required this.accountId,
    required this.dateIso,
    required this.amountMinor,
    required this.currencyCode,
  });

  final int accountId;
  final String dateIso; // yyyy-MM-dd
  final int amountMinor;
  final String currencyCode;

  static DedupeKey of({
    required int accountId,
    required DateTime date,
    required int amountMinor,
    required String currencyCode,
  }) =>
      DedupeKey(
        accountId: accountId,
        dateIso: date.toIso8601String().substring(0, 10),
        amountMinor: amountMinor,
        currencyCode: currencyCode.toUpperCase(),
      );

  @override
  bool operator ==(Object other) =>
      other is DedupeKey &&
      other.accountId == accountId &&
      other.dateIso == dateIso &&
      other.amountMinor == amountMinor &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode =>
      Object.hash(accountId, dateIso, amountMinor, currencyCode);

  @override
  String toString() => '$accountId|$dateIso|$amountMinor|$currencyCode';
}

/// Which dedupe verdict an imported row got.
enum DedupeVerdict { fresh, duplicateExact, duplicateSuspect }

/// Candidate import row scored against the existing ledger.
class DedupeResult<T> {
  const DedupeResult(this.item, this.verdict);
  final T item;
  final DedupeVerdict verdict;
}

class Dedupeer {
  /// Exact keys already present in the ledger.
  final Set<DedupeKey> existing;

  /// ± days tolerance for *suspect* (surfaced, never auto-dropped).
  final int suspectDayWindow;

  Dedupeer({required this.existing, this.suspectDayWindow = 2})
      : assert(suspectDayWindow >= 0);

  List<DedupeResult<T>> classify<T>(
      Iterable<T> incoming, DedupeKey Function(T) keyOf) {
    final seenThisBatch = <DedupeKey>{};
    return [
      for (final item in incoming)
        () {
          final k = keyOf(item);
          if (existing.contains(k) || seenThisBatch.contains(k)) {
            return DedupeResult(item, DedupeVerdict.duplicateExact);
          }
          seenThisBatch.add(k);
          if (_suspectNear(k)) {
            return DedupeResult(item, DedupeVerdict.duplicateSuspect);
          }
          return DedupeResult(item, DedupeVerdict.fresh);
        }(),
    ];
  }

  bool _suspectNear(DedupeKey k) {
    if (suspectDayWindow == 0) return false;
    final day = DateTime.parse(k.dateIso);
    for (var d = -suspectDayWindow; d <= suspectDayWindow; d++) {
      if (d == 0) continue;
      final probe = DedupeKey(
        accountId: k.accountId,
        dateIso: day.add(Duration(days: d)).toIso8601String().substring(0, 10),
        amountMinor: k.amountMinor,
        currencyCode: k.currencyCode,
      );
      if (existing.contains(probe)) return true;
    }
    return false;
  }
}
