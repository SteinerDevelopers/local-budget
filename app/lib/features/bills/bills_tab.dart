// #35 — Bills tab (design e3 §2.3). Rules are the truth; the notification
// is only a hint (§5). Rows sorted overdue → soonest (the repository's
// nextDue order), overdue date in `error`, due-within-3-days bold.
import 'package:core/core.dart' show Currency;
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import 'bill_detail_sheet.dart';
import 'bill_editor_sheet.dart';
import 'bills_service.dart';

/// The Bills slot inside the budgets sheet (§2.1). Dumb: the parent owns
/// loading; every mutation returns and the parent reloads.
class BillsTab extends StatelessWidget {
  const BillsTab({
    super.key,
    required this.repository,
    required this.bills,
    required this.currency,
    required this.categories,
    required this.onChanged,
  });

  final LedgerRepository repository;
  final List<BillLine> bills;
  final Currency currency;
  final List<Category> categories;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_repeat_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: Tokens.space3),
            Text('No bills yet', style: Tokens.body(context)),
            const SizedBox(height: Tokens.space1),
            Text(
              'Recurring payments you add here remind you the morning they fall due.',
              style: Tokens.labelCaps(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Tokens.space3),
            TextButton.icon(
              key: const Key('bill-add-empty'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add bill'),
              onPressed: () => _add(context),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            itemCount: bills.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, i) =>
                _BillRow(line: bills[i], onTap: () => _open(context, bills[i])),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('bill-add'),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add bill'),
                onPressed: () => _add(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final changed = await showBillEditor(
      context,
      repository: repository,
      currency: currency,
      categories: categories,
    );
    if (changed == true) await onChanged();
  }

  Future<void> _open(BuildContext context, BillLine line) async {
    final result = await showBillDetail(
      context,
      repository: repository,
      line: line,
      categories: categories,
    );
    if (result == _openEditor) {
      if (!context.mounted) return;
      await _edit(context, line);
    } else if (result != null) {
      await onChanged();
    }
  }

  Future<void> _edit(BuildContext context, BillLine line) async {
    final changed = await showBillEditor(
      context,
      repository: repository,
      currency: currency,
      categories: categories,
      line: line,
    );
    if (changed == true) await onChanged();
  }
}

/// Sentinel result telling the parent "detail closed on Edit rule".
const String _openEditor = 'edit';

class _BillRow extends StatelessWidget {
  const _BillRow({required this.line, required this.onTap});

  final BillLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color dueColor, FontWeight dueWeight) = switch (line.state) {
      BillDueState.overdue => (scheme.error, FontWeight.w400),
      BillDueState.dueSoon => (scheme.onSurface, FontWeight.w600),
      BillDueState.later => (scheme.onSurfaceVariant, FontWeight.w400),
    };
    return InkWell(
      key: Key('bill-row-${line.rule.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(
              ManageIcons.of(
                line.category?.icon,
                line.category?.name ?? line.rule.name,
              ),
              size: 24,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.rule.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(context),
                  ),
                  Text.rich(
                    TextSpan(
                      children: line.isStale
                          ? [
                              // §3.4: over a year without materializing —
                              // the row asks the question the pass asks.
                              const TextSpan(text: 'Paused? · '),
                              TextSpan(text: line.dueText),
                            ]
                          : [
                              const TextSpan(text: 'Due '),
                              TextSpan(text: line.dueText),
                            ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: dueColor,
                      fontWeight: dueWeight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Text(
              line.amount.format(),
              style: TextStyle(
                fontSize: Tokens.bodySize,
                fontWeight: FontWeight.w500,
                color: line.isOverdue ? scheme.error : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
