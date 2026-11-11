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

/// Recurring-charge detector (E7 §2.2, `docs/design/e7-paid-pack.md`).
/// Pure function over [EngineTx] rows — same tier-1 discipline as the rest
/// of the package: no clocks, no I/O, deterministic on fixtures.
///
/// Output is *suggestions* only: the UI turns one into an E3 recurring bill
/// through the existing editor sheet after a tap. Nothing is ever
/// auto-applied, so v1 deliberately favors precision over recall — a
/// merchant that skipped one cycle simply is not detected until its window
/// realigns, rather than firing a shaky card.
library;

import 'dart:math' as math;

import 'period.dart';

/// One detected pattern. Amounts are base-currency minor units; days are
/// epoch days (engine convention — the UI formats).
final class RecurringSuggestion {
  const RecurringSuggestion({
    required this.merchantName,
    required this.hits,
    required this.cadenceDays,
    required this.amountAvgMinor,
    required this.amountCoVbp,
    required this.firstDay,
    required this.lastDay,
    required this.totalMinor,
  });

  /// Display name from the most recent matching row (raw case as saved).
  final String merchantName;

  /// Number of monthly hits (same-day rows merge into one hit — two split
  /// receipts at the same merchant are one cycle, not two).
  final int hits;

  /// Median of consecutive hit-to-hit spacings (27–33 by construction).
  final int cadenceDays;

  final int amountAvgMinor;

  /// Amount variation, basis points (1500 = the 15 % ceiling by default).
  final int amountCoVbp;

  final int firstDay;
  final int lastDay;
  final int totalMinor;
}

/// Stateless group-and-screen detector, called off the build (60 fps
/// contract): the repository loads rows, this runs once, the widget list
/// renders.
abstract final class RecurringDetector {
  /// Merchant grouping key: lowercase, alphanumeric only. Deliberately
  /// local and boring — "UBER *TRIP", "uber trip", "Uber.Trip" are one
  /// pattern; anything fancier belongs in the capture normalizer, not the
  /// report engine.
  static String canonicalMerchant(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static List<RecurringSuggestion> suggest(
    List<EngineTx> transactions, {
    int minHits = 3,
    int minGapDays = 27,
    int maxGapDays = 33,
    int maxCoVBp = 1500,
  }) {
    // canonical key -> (epoch day -> summed amount), plus display identity.
    final byDay = <String, Map<int, int>>{};
    final display = <String, String>{};
    final displayDay = <String, int>{};
    for (final t in transactions) {
      final raw = t.merchantName;
      if (raw == null || !t.countsTowardBudgets) continue;
      final key = canonicalMerchant(raw);
      if (key.isEmpty) continue;
      byDay.putIfAbsent(key, () => <int, int>{}).update(
          t.dateDays, (v) => v + t.baseAmountMinor,
          ifAbsent: () => t.baseAmountMinor);
      if (t.dateDays >= (displayDay[key] ?? -1)) {
        display[key] = raw;
        displayDay[key] = t.dateDays;
      }
    }

    final out = <RecurringSuggestion>[];
    for (final entry in byDay.entries) {
      final days = entry.value.keys.toList()..sort();
      if (days.length < minHits) continue;
      final gaps = [
        for (var i = 1; i < days.length; i++) days[i] - days[i - 1]
      ];
      // Strict cadence band (spec §2.2): every spacing must be monthly.
      if (gaps.any((g) => g < minGapDays || g > maxGapDays)) continue;
      final amounts = [for (final d in days) entry.value[d]!];
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      if (mean <= 0) continue;
      final variance =
          amounts.fold<double>(0, (s, a) => s + (a - mean) * (a - mean)) /
              amounts.length;
      final coVbp = (math.sqrt(variance) / mean * 10000).round();
      if (coVbp > maxCoVBp) continue;
      gaps.sort();
      final total = amounts.reduce((a, b) => a + b);
      out.add(RecurringSuggestion(
        merchantName: display[entry.key]!,
        hits: days.length,
        cadenceDays: gaps[gaps.length ~/ 2],
        amountAvgMinor: (total ~/ amounts.length),
        amountCoVbp: coVbp,
        firstDay: days.first,
        lastDay: days.last,
        totalMinor: total,
      ));
    }
    // Biggest recurring footprint first; ties by display name (deterministic
    // for goldens).
    out.sort((a, b) => a.totalMinor != b.totalMinor
        ? b.totalMinor.compareTo(a.totalMinor)
        : a.merchantName.compareTo(b.merchantName));
    return out;
  }
}
