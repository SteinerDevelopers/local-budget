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

// E7 §2.1 — the range sheet behind the Insights segment's header chip:
// four presets plus a custom two-date pick. Preset math lives in
// analytics_service.dart (unit-tested); this file only picks.
import 'package:budget/budget.dart' show DayRange, dayOf;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'analytics_service.dart';

/// Returns the chosen [DayRange] (closed-open), or null if dismissed.
Future<DayRange?> showRangeSheet(
  BuildContext context, {
  required DateTime today,
  required DayRange current,
}) => showModalBottomSheet<DayRange>(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => _RangeSheet(today: today, current: current),
);

class _RangeSheet extends StatelessWidget {
  const _RangeSheet({required this.today, required this.current});

  final DateTime today;
  final DayRange current;

  Future<void> _pickCustom(BuildContext context) async {
    // A budget app never reports the future; ten years back is generous
    // for imported history and keeps the picker keyboard-free.
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 10),
      lastDate: DateTime(today.year + 1),
      helpText: 'Custom range',
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop(
      DayRange(
        startDay: dayOf(picked.start),
        // The picker's end is inclusive; engine ranges are not.
        endDay: dayOf(picked.end) + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Tokens.space2),
          Text('Report range', style: Tokens.monthTitle(context)),
          const SizedBox(height: Tokens.space2),
          for (final p in RangePreset.values)
            Builder(
              builder: (context) {
                // DayRange is a value-plain record: compare the boundaries,
                // never the object.
                final r = dayRangeFor(p, today: today);
                final on =
                    r.startDay == current.startDay &&
                    r.endDay == current.endDay;
                return ListTile(
                  key: Key('range-preset-${p.name}'),
                  leading: Icon(
                    on ? Icons.radio_button_checked : Icons.radio_button_off,
                  ),
                  title: Text(p.label),
                  subtitle: Text(formatRangeLabel(r)),
                  onTap: () => Navigator.of(context).pop(r),
                );
              },
            ),
          ListTile(
            key: const Key('range-preset-custom'),
            leading: const Icon(Icons.calendar_today),
            title: const Text('Custom dates'),
            onTap: () => _pickCustom(context),
          ),
          const SizedBox(height: Tokens.space2),
        ],
      ),
    );
  }
}
