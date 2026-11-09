// #35 — bill rule editor (design e3 §2.3): name, keypad amount (base
// currency), Weekly | Monthly | Yearly + day semantics, category chip,
// Notify switch, start month switcher. Bills are rules, never transactions
// (§3.4); this sheet only stores the rule and schedules its hint (§5).
import 'dart:math' as math;

import 'package:budget/budget.dart' show BillFrequency;
import 'package:core/core.dart' show BillFrequencyHint, Currency;
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

/// Add-mode head start: an E7 Insights suggestion (§2.2) or an E11 bill
/// document. The merchant and amount arrive filled; the owner still taps
/// Save — prefills are never applied without a tap. [dueDate] seeds the
/// start month and day-of-month cursor (e11 §4); [fromDocument] only
/// changes the header note, never the save path.
final class BillPrefill {
  const BillPrefill({
    required this.name,
    required this.amountMinor,
    this.dueDate,
    this.frequency,
    this.fromDocument = false,
  });

  final String name;
  final int amountMinor;

  /// Parsed due date (e11) — the first-due cursor for the new rule.
  final DateTime? dueDate;

  /// Recurrence read from the document (e12 §1) — the wizard only passes a
  /// high-confidence hint; it prefills the chip, review stays required.
  final BillFrequencyHint? frequency;

  /// True only for the document route: the editor says where it came from.
  final bool fromDocument;
}

/// [line] non-null = edit mode; add mode starts today with sensible days.
/// [prefill] only applies to add mode ([line] null).
Future<bool?> showBillEditor(
  BuildContext context, {
  required LedgerRepository repository,
  required Currency currency,
  required List<Category> categories,
  BillLine? line,
  BillPrefill? prefill,
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
    prefill: prefill,
  ),
);

class _BillEditorSheet extends StatefulWidget {
  const _BillEditorSheet({
    required this.repository,
    required this.currency,
    required this.categories,
    required this.line,
    required this.prefill,
  });

  final LedgerRepository repository;
  final Currency currency;
  final List<Category> categories;
  final BillLine? line;
  final BillPrefill? prefill;

  @override
  State<_BillEditorSheet> createState() => _BillEditorSheetState();
}

class _BillEditorSheetState extends State<_BillEditorSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.currency);
  late final TextEditingController _name = TextEditingController(
    text: widget.line?.rule.name ?? widget.prefill?.name ?? '',
  );

  // Edit mode keeps the stored cadence; a document prefill preselects the
  // hint the wizard read (e12 §1); the plain add starts monthly.
  late BillFrequency _freq = widget.line != null
      ? BillFrequency.fromStorage(widget.line!.rule.frequency)
      : widget.prefill?.frequency != null
      ? BillFrequency.fromStorage(widget.prefill!.frequency!.wireName)
      : BillFrequency.monthly;
  // E11 §4: a document's due date seeds the cursor — start month and day
  // come from it, so the first occurrence lands exactly where the bill says.
  late int _dom =
      widget.line?.rule.dayOfMonth ??
      widget.prefill?.dueDate?.day ??
      DateTime.now().day;
  late int _dow =
      widget.line?.rule.dayOfWeek ??
      widget.prefill?.dueDate?.weekday ??
      DateTime.now().weekday;
  late int? _categoryId = widget.line?.rule.categoryId;
  late bool _notify = widget.line?.rule.notify ?? true;
  late int _startIdx = widget.line != null
      ? monthIndexOf(
          DateTime.fromMillisecondsSinceEpoch(widget.line!.rule.startMs),
        )
      : monthIndexOf(widget.prefill?.dueDate ?? DateTime.now());

  bool get _isAdd => widget.line == null;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _pad.money.isPositive &&
      _categoryId != null;

  @override
  void initState() {
    super.initState();
    // The keypad starts from the stored amount (edit) or the suggested
    // average (E7 prefill); same digit-loop seeding either way.
    final minor = widget.line?.rule.amountMinor ?? widget.prefill?.amountMinor;
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
    // e12 §1: the biweekly ladder anchors on a date, so the start pins to
    // the picked day of the start month; the engine ignores dayOfMonth for
    // that kind. Everything else starts on the month and recurs by dom/dow.
    final biweekly = _freq == BillFrequency.biweekly;
    final start = biweekly
        ? DateTime(
            startMonth.year,
            startMonth.month,
            math.min(
              _dom,
              DateTime(startMonth.year, startMonth.month + 1, 0).day,
            ),
          )
        : startMonth;
    final dueEpoch = firstDueOnOrAfter(
      frequency: _freq,
      dayOfMonth: _freq == BillFrequency.weekly || biweekly ? null : _dom,
      dayOfWeek: _freq == BillFrequency.weekly ? _dow : null,
      startEpochDay: epochDayOf(start),
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
        start: start,
        nextDue: due,
        categoryId: _categoryId,
        dayOfMonth: _freq == BillFrequency.weekly || biweekly ? null : _dom,
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
        start: start,
        nextDue: due,
        categoryId: _categoryId,
        dayOfMonth: _freq == BillFrequency.weekly || biweekly ? null : _dom,
        dayOfWeek: _freq == BillFrequency.weekly ? _dow : null,
        notify: _notify,
      );
      await BillNotifier.cancel(ruleId);
    }
    if (_notify) {
      await BillNotifier.schedule(ruleId: ruleId, name: name, due: due, askPermission: true);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // The bill editor is inherently tall, so it keeps its shipped 92 % of
    // the screen (device feedback 2026-11-04 pm kept the fraction — a
    // shorter sheet buries the pad's bottom row behind the portrait scroll
    // fold, which silently swallows keypad taps). Font-scale slack comes
    // from inside: fixed rows grow with the system font and the keypad
    // gives down to its 4×touch-min scroll floor. In landscape that stack
    // cannot fit the short screen — the tester's stripe of a pad clipped
    // mid-row — so the pad gets its own right-hand pane and the fields
    // scroll beside it.
    final size = MediaQuery.sizeOf(context);
    final height = size.height * 0.92;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          // A scroll-controlled sheet sits flush with the physical bottom
          // of the screen — modal useSafeArea deliberately never insets
          // it there — so the system navigation bar is ours to clear
          // (device feedback 2026-11-04 pm: 3-button devices painted
          // "Add bill" underneath the bar).
          padding: EdgeInsets.only(
            bottom: Tokens.space4 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: Tokens.space2),
              _dragBar(context),
              if (_isAdd && widget.prefill?.fromDocument == true)
                // e11 §4 — provenance under the header, before any field.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'We read this from your document — check it before saving.',
                    key: const Key('bill-prefill-note'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _startRow(),
              Expanded(
                child: size.width > size.height ? _landscape() : _portrait(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- sheet pieces (same grammar as QuickAdd's sheet) ------------------

  Widget _portrait() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _fields(),
      // The shell pads only its bottom — every piece insets itself in
      // this sheet — and the hero had no inset: on-device it painted
      // "$36" flush against the screen edge (Coosea capture, 2026-11-05).
      // QuickAdd wraps its whole content at space4; match that here.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        child: AmountDisplay(pad: _pad, currency: widget.currency),
      ),
      Expanded(
        // Below 4×touch-min the pad stops growing and scrolls instead of
        // pushing Notify/Save off the sheet — every key stays tappable
        // even at extreme font scales.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: SizedBox(
              height: math.max(box.maxHeight, 4 * Tokens.touchMin),
              child: _keypad(),
            ),
          ),
        ),
      ),
      _notifyTile(),
      _saveButton(),
    ],
  );

  Widget _landscape() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 3,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fields(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
                child: AmountDisplay(pad: _pad, currency: widget.currency),
              ),
              _notifyTile(),
              const SizedBox(height: Tokens.space2),
              _saveButton(),
            ],
          ),
        ),
      ),
      const SizedBox(width: Tokens.space2),
      Expanded(flex: 2, child: _keypad()),
    ],
  );

  Widget _fields() => Padding(
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
              CategoryOption(c.id, c.name, ManageIcons.of(c.icon, c.name)),
          ],
          selectedId: _categoryId,
          onSelect: (id) => setState(() => _categoryId = id),
          onManage: null,
        ),
        const SizedBox(height: Tokens.space3),
        FittedBox(
          // Five cadences must stay honest-readable on a 360 dp phone: the
          // segment row scales down instead of scrolling off (e12 §1).
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegmentedButton<BillFrequency>(
            segments: const [
              ButtonSegment(value: BillFrequency.weekly, label: Text('Weekly')),
              ButtonSegment(
                value: BillFrequency.biweekly,
                label: Text('Biweekly'),
              ),
              ButtonSegment(
                value: BillFrequency.monthly,
                label: Text('Monthly'),
              ),
              ButtonSegment(
                value: BillFrequency.quarterly,
                label: Text('Quarterly'),
              ),
              ButtonSegment(value: BillFrequency.yearly, label: Text('Yearly')),
            ],
            selected: {_freq},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _freq = s.first),
          ),
        ),
        const SizedBox(height: Tokens.space2),
        _daySelector(),
      ],
    ),
  );

  Widget _keypad() => Keypad(
    onDigit: (d) => setState(() => _pad.digit(d)),
    onDot: () => setState(() => _pad.dot()),
    onBackspace: () => setState(() => _pad.back()),
  );

  Widget _notifyTile() => SwitchListTile(
    key: const Key('bill-notify'),
    title: const Text('Notify me the morning it is due'),
    secondary: const Icon(Icons.notifications_none),
    value: _notify,
    onChanged: (v) => setState(() => _notify = v),
  );

  Widget _saveButton() => Padding(
    padding: const EdgeInsets.fromLTRB(
      Tokens.space4,
      Tokens.space2,
      Tokens.space4,
      0,
    ),
    child: SizedBox(
      width: double.infinity,
      // min-height, not a tight box: the M3 button grows with the font
      // instead of clipping it.
      height: Tokens.touchMin,
      child: FilledButton(
        key: const Key('bill-save'),
        onPressed: _canSave ? _save : null,
        child: Text(_isAdd ? 'Add bill' : 'Save changes'),
      ),
    ),
  );

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
