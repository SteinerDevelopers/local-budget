// #37 — Goal detail (design e3 §2.4): progress, the transfer list, and
// the two keypad sheets (`Add to goal` / `Withdraw`). A transfer is a
// transaction row with goalId; the isIncome bit is only the direction
// here — nowhere else does it mean income (§3.5).
// Returns 'edit' to ask the tab to open the editor; any dismissal lets the
// tab reload unconditionally (transfers mutate the sheet in place, so a
// swipe-close must not skip the list refresh).
import 'dart:math' as math;

import 'package:core/core.dart' show Currency, Money;
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import '../quickadd/amount_display.dart';
import '../quickadd/amount_pad.dart';
import '../quickadd/keypad.dart';
import 'goals_service.dart';

Future<String?> showGoalDetail(
  BuildContext context, {
  required LedgerRepository repository,
  required GoalLine line,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _GoalDetailSheet(repository: repository, line: line),
);

class _GoalDetailSheet extends StatefulWidget {
  const _GoalDetailSheet({required this.repository, required this.line});

  final LedgerRepository repository;
  final GoalLine line;

  @override
  State<_GoalDetailSheet> createState() => _GoalDetailSheetState();
}

class _GoalDetailSheetState extends State<_GoalDetailSheet> {
  late GoalLine _line = widget.line;
  List<Transaction> _transfers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final transfers = await widget.repository.goalTransfers(_line.goal.id);
    final line = await reloadGoalLine(widget.repository, _line.goal.id);
    if (!mounted) return;
    setState(() {
      _transfers = transfers;
      _line = line;
    });
  }

  Future<void> _transfer({required bool withdraw}) async {
    final minor = await showAmountSheet(
      context,
      currency: _line.currency,
      title: withdraw ? 'Withdraw' : 'Add to goal',
      cta: withdraw ? 'Withdraw' : 'Add',
    );
    if (minor == null || minor <= 0) return;
    await widget.repository.addGoalTransfer(
      accountId: (await widget.repository.defaultAccount()).id,
      goalId: _line.goal.id,
      date: DateTime.now(),
      amount: Money(minor, _line.currency),
      isIncome: withdraw,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = _line;
    final fraction = line.fraction;
    return SizedBox(
      height: math.max(520.0, MediaQuery.sizeOf(context).height * 0.72),
      child: Padding(
        // Deposit/Withdraw are the sheet's last row — clear the nav bar
        // strip (Tokens.sheetBottomInset; 2026-11-04 pm second wave).
        padding: EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space2,
          Tokens.space4,
          Tokens.space3 + Tokens.sheetBottomInset(context),
        ),
        child: Column(
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
            const SizedBox(height: Tokens.space2),
            Row(
              children: [
                Icon(
                  ManageIcons.of(line.goal.icon, line.goal.name),
                  size: 28,
                  color: scheme.primary,
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: Text(
                    line.goal.name,
                    style: Tokens.monthTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  key: const Key('goal-edit'),
                  onPressed: () => Navigator.of(context).pop('edit'),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space1),
            Text(
              line.target == null
                  ? '${line.saved.format()} saved'
                  : '${line.saved.format()} / ${line.target!.format()}',
              style: Tokens.body(context),
            ),
            if (fraction != null) ...[
              const SizedBox(height: Tokens.space2),
              _ProgressBar(fraction: fraction),
              const SizedBox(height: Tokens.space1),
              Text(
                '${(fraction * 100).round()}% saved',
                style: Tokens.labelCaps(context),
              ),
            ],
            if (line.goal.note != null && line.goal.note!.isNotEmpty) ...[
              const SizedBox(height: Tokens.space2),
              Text(
                line.goal.note!,
                style: Tokens.body(
                  context,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Tokens.space3),
            Expanded(
              child: _transfers.isEmpty
                  ? Center(
                      child: Text(
                        'No transfers yet — add the first one below.',
                        style: Tokens.labelCaps(context),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _transfers.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, i) => _TransferRow(
                        tx: _transfers[i],
                        currency: line.currency,
                      ),
                    ),
            ),
            const SizedBox(height: Tokens.space2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('goal-withdraw'),
                    onPressed: line.savedMinor <= 0
                        ? null
                        : () => _transfer(withdraw: true),
                    child: const Text('Withdraw'),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: FilledButton(
                    key: const Key('goal-deposit'),
                    onPressed: () => _transfer(withdraw: false),
                    child: const Text('Add to goal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.4 detail progress — same bar language as the rows, 6 dp tall so it
/// reads as the sheet's hero number's underline.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.tx, required this.currency});

  final Transaction tx;
  final Currency currency;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = dateFromEpochDay(tx.dateDays);
    final withdraw = tx.isIncome; // §3.5: direction bit, not income
    return Padding(
      key: Key('goal-transfer-${tx.id}'),
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.note?.isNotEmpty == true
                      ? tx.note!
                      : (withdraw ? 'Withdraw' : 'Deposit'),
                  style: Tokens.body(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${date.day} ${_months[date.month - 1]} ${date.year}',
                  style: Tokens.labelCaps(context),
                ),
              ],
            ),
          ),
          Text(
            '${withdraw ? '−' : '+'}${Money(tx.amountMinor, currency).format()}',
            style: Tokens.body(context).copyWith(
              color: withdraw ? scheme.onSurfaceVariant : scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared keypad amount sheet for both transfer directions — the same
/// digits-only grammar as QuickAdd and the limit editor.
Future<int?> showAmountSheet(
  BuildContext context, {
  required Currency currency,
  required String title,
  required String cta,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _AmountSheet(currency: currency, title: title, cta: cta),
);

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.currency,
    required this.title,
    required this.cta,
  });

  final Currency currency;
  final String title;
  final String cta;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.currency);

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.max(440.0, MediaQuery.sizeOf(context).height * 0.5),
        child: Padding(
          // Fixed-height box under a keyboard-lift: nav-bar clearance
          // belongs INSIDE the box (bill_editor grammar). The keypad
          // never raises a keyboard, so the lift above stays at zero —
          // the Confirm row still owed the 3-button bar (2026-11-04 pm
          // second wave).
          padding: EdgeInsets.fromLTRB(
            Tokens.space4,
            Tokens.space2,
            Tokens.space4,
            Tokens.space4 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Tokens.space2),
              Text(widget.title, style: Tokens.monthTitle(context)),
              const SizedBox(height: Tokens.space3),
              AmountDisplay(pad: _pad, currency: widget.currency),
              Expanded(
                child: Keypad(
                  onDigit: (d) => setState(() => _pad.digit(d)),
                  onDot: () => setState(_pad.dot),
                  onBackspace: () => setState(_pad.back),
                  dotEnabled: widget.currency.minorUnits > 0,
                ),
              ),
              const SizedBox(height: Tokens.space2),
              FilledButton(
                key: const Key('goal-amount-confirm'),
                onPressed: _pad.money.isPositive
                    ? () => Navigator.of(context).pop(_pad.money.minorUnits)
                    : null,
                child: Text(widget.cta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
