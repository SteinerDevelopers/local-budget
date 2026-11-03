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
