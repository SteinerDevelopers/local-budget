// #35 — bill rule editor (design e3 §2.3): name, keypad amount (base
// currency), Weekly | Monthly | Yearly + day semantics, category chip,
// Notify switch, start month switcher. Bills are rules, never transactions
// (§3.4); this sheet only stores the rule and schedules its hint (§5).
import 'dart:math' as math;

import 'package:budget/budget.dart' show BillFrequency;
import 'package:core/core.dart' show Currency;
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ledger/ledger_screen.dart' show monthIndexOf, monthTitle;
import '../manage/icon_registry.dart';
import '../quickadd/amount_display.dart';
import '../quickadd/amount_pad.dart';
import '../quickadd/category_chips.dart';
import '../quickadd/keypad.dart';
import '../quickadd/quick_add_sheet.dart' show CategoryOption;
import 'bill_notifier.dart';
import 'bills_service.dart';

/// [line] non-null = edit mode; add mode starts today with sensible days.
Future<bool?> showBillEditor(
  BuildContext context, {
  required LedgerRepository repository,
  required Currency currency,
  required List<Category> categories,
  BillLine? line,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  isDismissible: false,
  builder: (_) => _BillEditorSheet(
    repository: repository,
    currency: currency,
    categories: categories,
    line: line,
  ),
);

class _BillEditorSheet extends StatefulWidget {
  const _BillEditorSheet({
    required this.repository,
    required this.currency,
    required this.categories,
    required this.line,
  });

  final LedgerRepository repository;
  final Currency currency;
  final List<Category> categories;
  final BillLine? line;

  @override
  State<_BillEditorSheet> createState() => _BillEditorSheetState();
}

class _BillEditorSheetState extends State<_BillEditorSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.currency);
  late final TextEditingController _name = TextEditingController(
    text: widget.line?.rule.name ?? '',
  );

  late BillFrequency _freq = widget.line == null
      ? BillFrequency.monthly
      : BillFrequency.fromStorage(widget.line!.rule.frequency);
  late int _dom = widget.line?.rule.dayOfMonth ?? DateTime.now().day;
  late int _dow = widget.line?.rule.dayOfWeek ?? DateTime.now().weekday;
  late int? _categoryId = widget.line?.rule.categoryId;
  late bool _notify = widget.line?.rule.notify ?? true;
  late int _startIdx = widget.line == null
      ? monthIndexOf(DateTime.now())
      : monthIndexOf(
          DateTime.fromMillisecondsSinceEpoch(widget.line!.rule.startMs),
        );

  bool get _isAdd => widget.line == null;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _pad.money.isPositive &&
      _categoryId != null;

  @override
  void initState() {
    super.initState();
    final minor = widget.line?.rule.amountMinor;
    if (minor != null && minor > 0) {
      final pow10 = _pow10(widget.currency.minorUnits);
      for (final d in (minor ~/ pow10).toString().split('')) {
        _pad.digit(d);
      }
      final frac = minor % pow10;
      if (frac > 0) {
        _pad.dot();
        var f = frac.toString().padLeft(2, '0');
        if (f.endsWith('0')) f = f.substring(0, f.length - 1);
        for (final d in f.split('')) {
          _pad.digit(d);
        }
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final startMonth = DateTime(2000 + _startIdx ~/ 12, _startIdx % 12 + 1);
    final dueEpoch = firstDueOnOrAfter(
      frequency: _freq,
      dayOfMonth: _freq == BillFrequency.weekly ? null : _dom,
      dayOfWeek: _freq == BillFrequency.weekly ? _dow : null,
      startEpochDay: epochDayOf(startMonth),
    );
    final due = dayFromEpoch(dueEpoch);
    final name = _name.text.trim();
    final int ruleId;
    if (_isAdd) {
      ruleId = await widget.repository.addRule(
        name: name,
        amountMinor: _pad.money.minorUnits,
        currencyCode: widget.currency.code,
        frequency: _freq.storageKey,
        start: startMonth,
        nextDue: due,
        categoryId: _categoryId,
        dayOfMonth: _freq == BillFrequency.weekly ? null : _dom,
        dayOfWeek: _freq == BillFrequency.weekly ? _dow : null,
        notify: _notify,
      );
    } else {
      final RecurringRule r = widget.line!.rule;
      ruleId = r.id;
      await widget.repository.updateRule(
        id: ruleId,
        name: name,
        amountMinor: _pad.money.minorUnits,
        frequency: _freq.storageKey,
        start: startMonth,
        nextDue: due,
        categoryId: _categoryId,
        dayOfMonth: _freq == BillFrequency.weekly ? null : _dom,
        dayOfWeek: _freq == BillFrequency.weekly ? _dow : null,
        notify: _notify,
      );
      await BillNotifier.cancel(ruleId);
    }
    if (_notify) {
      await BillNotifier.schedule(ruleId: ruleId, name: name, due: due);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: math.max(560.0, MediaQuery.sizeOf(context).height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: Tokens.space2),
            _dragBar(context),
            _startRow(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              child: Column(
                children: [
                  TextField(
                    key: const Key('bill-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Bill name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Tokens.space3),
                  CategoryChips(
                    key: const Key('bill-categories'),
                    categories: [
                      for (final c in widget.categories)
                        CategoryOption(
                          c.id,
                          c.name,
                          ManageIcons.of(c.icon, c.name),
                        ),
                    ],
                    selectedId: _categoryId,
                    onSelect: (id) => setState(() => _categoryId = id),
                    onManage: null,
                  ),
                  const SizedBox(height: Tokens.space3),
                  SegmentedButton<BillFrequency>(
                    segments: const [
                      ButtonSegment(
                        value: BillFrequency.weekly,
                        label: Text('Weekly'),
                      ),
                      ButtonSegment(
                        value: BillFrequency.monthly,
                        label: Text('Monthly'),
                      ),
                      ButtonSegment(
                        value: BillFrequency.yearly,
                        label: Text('Yearly'),
                      ),
                    ],
                    selected: {_freq},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _freq = s.first),
                  ),
                  const SizedBox(height: Tokens.space2),
                  _daySelector(),
                ],
              ),
            ),
            // Keypad takes every leftover pixel (its keys are Expanded
            // rows), so it doubles as the Spacer here — same trick as
            // QuickAdd's sheet.
            AmountDisplay(pad: _pad, currency: widget.currency),
            Expanded(
              child: Keypad(
                onDigit: (d) => setState(() => _pad.digit(d)),
                onDot: () => setState(() => _pad.dot()),
                onBackspace: () => setState(() => _pad.back()),
              ),
            ),
            SwitchListTile(
              key: const Key('bill-notify'),
              title: const Text('Notify me the morning it is due'),
              secondary: const Icon(Icons.notifications_none),
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space4,
                Tokens.space2,
                Tokens.space4,
                Tokens.space4,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('bill-save'),
                  onPressed: _canSave ? _save : null,
                  child: Text(_isAdd ? 'Add bill' : 'Save changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dragBar(BuildContext context) => Center(
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
  );

  /// Start month switcher (§2.3) — the ledger sheet's chevron pattern.
  Widget _startRow() => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          key: const Key('bill-start-prev'),
          icon: const Icon(Icons.chevron_left, size: 28),
          tooltip: 'Earlier month',
          onPressed: () => setState(() => _startIdx -= 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              'Starts ${monthTitle(_startIdx)}',
              style: const TextStyle(
                fontSize: Tokens.bodySize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('bill-start-next'),
          icon: const Icon(Icons.chevron_right, size: 28),
          tooltip: 'Later month',
          onPressed: () => setState(() => _startIdx += 1),
        ),
      ],
    ),
  );

  Widget _daySelector() => SizedBox(
    height: 40,
    child: _freq == BillFrequency.weekly
        ? ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var d = 1; d <= 7; d++)
                Padding(
                  padding: const EdgeInsets.only(right: Tokens.space2),
                  child: FilterChip(
                    key: Key('dow-$d'),
                    selected: _dow == d,
                    onSelected: (_) => setState(() => _dow = d),
                    label: Text(_wdLabels[d - 1]),
                  ),
                ),
            ],
          )
        : ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var d = 1; d <= 31; d++)
                Padding(
                  padding: const EdgeInsets.only(right: Tokens.space2),
                  child: FilterChip(
                    key: Key('dom-$d'),
                    selected: _dom == d,
                    onSelected: (_) => setState(() => _dom = d),
                    label: Text('$d'),
                  ),
                ),
            ],
          ),
  );
}

const List<String> _wdLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

int _pow10(int n) {
  var p = 1;
  for (var i = 0; i < n; i++) {
    p *= 10;
  }
  return p;
}
