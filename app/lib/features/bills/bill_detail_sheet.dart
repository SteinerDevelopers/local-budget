// #35 — occurrence detail sheet (design e3 §2.3 "Row tap"). The row's only
// actions: Mark paid (§3.4's explicit materialization — a real transaction
// through QuickAdd's path), Edit rule, Delete rule.
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import 'bill_notifier.dart';
import 'bills_service.dart';

/// Returns a result token: 'paid' | 'deleted' | 'edit' | null.
Future<String?> showBillDetail(
  BuildContext context, {
  required LedgerRepository repository,
  required BillLine line,
  required List<Category> categories,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _BillDetailSheet(
    repository: repository,
    line: line,
    categories: categories,
  ),
);

class _BillDetailSheet extends StatelessWidget {
  const _BillDetailSheet({
    required this.repository,
    required this.line,
    required this.categories,
  });

  final LedgerRepository repository;
  final BillLine line;
  final List<Category> categories;

  String get _frequencyText {
    final r = line.rule;
    return switch (r.frequency) {
      'weekly' => 'Weekly · ${billWeekdayShort(r.dayOfWeek ?? 1)}',
      'yearly' => 'Yearly · every ${_nth(r.dayOfMonth ?? 1)}',
      _ => 'Monthly · ${_nth(r.dayOfMonth ?? 1)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = line.category;
    return Padding(
      // The sheet's Delete row is the last thing it paints — it must
      // clear the nav bar strip (Tokens.sheetBottomInset; device
      // feedback 2026-11-04 pm second wave).
      padding: EdgeInsets.fromLTRB(
        Tokens.space4,
        Tokens.space2,
        Tokens.space4,
        Tokens.space4 + Tokens.sheetBottomInset(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Tokens.space4),
          Row(
            children: [
              Icon(
                ManageIcons.of(cat?.icon, cat?.name ?? line.rule.name),
                size: 28,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Text(
                  line.rule.name,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                line.amount.format(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: line.isStale ? 'Paused? ' : 'Due '),
                TextSpan(
                  text: line.dueText,
                  style: line.isOverdue
                      ? TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                TextSpan(
                  text: ' · ${line.rule.notify ? 'notified' : 'silent'}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            style: TextStyle(fontSize: Tokens.bodySize),
          ),
          const SizedBox(height: Tokens.space1),
          Text(
            _frequencyText,
            style: Tokens.labelCaps(
              context,
            ).copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Tokens.space5),
          if (line.isStale) ...[
            // §3.4: a rule this stale never auto-inserts; the sheet asks
            // "paused?" and lets the user answer either way.
            Text(
              'This bill hasn’t come due in over a year. Resume it, or pause '
              'it so it stops asking.',
              style: Tokens.body(context),
            ),
            const SizedBox(height: Tokens.space3),
            FilledButton.icon(
              key: const Key('bill-resume'),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Resume from today'),
              onPressed: () async {
                await resumeBill(repository, line);
                if (context.mounted) Navigator.of(context).pop('resumed');
              },
            ),
            const SizedBox(height: Tokens.space2),
            TextButton.icon(
              key: const Key('bill-pause'),
              icon: const Icon(Icons.pause, size: 20),
              label: const Text('Pause this bill'),
              onPressed: () async {
                await pauseBill(repository, line);
                if (context.mounted) Navigator.of(context).pop('paused');
              },
            ),
          ] else
            FilledButton.icon(
              key: const Key('bill-mark-paid'),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Mark paid'),
              onPressed: () async {
                await markBillPaid(repository, line);
                if (context.mounted) Navigator.of(context).pop('paid');
              },
            ),
          const SizedBox(height: Tokens.space2),
          TextButton.icon(
            key: const Key('bill-edit'),
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: const Text('Edit rule'),
            onPressed: () => Navigator.of(context).pop('edit'),
          ),
          TextButton.icon(
            key: const Key('bill-delete'),
            icon: const Icon(Icons.delete_outline, size: 20),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            label: const Text('Delete rule'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this bill?'),
                  content: Text(
                    'The rule goes away. Payments already recorded stay '
                    'in your ledger.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const Key('bill-delete-confirm'),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await BillNotifier.cancel(line.rule.id);
              await repository.deleteRule(line.rule.id);
              if (context.mounted) Navigator.of(context).pop('deleted');
            },
          ),
        ],
      ),
    );
  }
}

String _nth(int day) => switch (day) {
  1 => '1st',
  2 => '2nd',
  3 => '3rd',
  21 => '21st',
  22 => '22nd',
  23 => '23rd',
  31 => '31st',
  _ => '${day}th',
};
