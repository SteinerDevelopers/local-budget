import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ledger/day_label.dart';
import '../ledger/view_models.dart';
import 'amount_display.dart';
import 'amount_pad.dart';
import 'category_chips.dart';
import 'currency_choice_sheet.dart';
import 'keypad.dart';

/// A category as QuickAdd renders it (icon + label). #18 sources these from
/// drift; the sheet only consumes the list.
@immutable
class CategoryOption {
  const CategoryOption(this.id, this.name, this.icon);
  final int id;
  final String name;
  final IconData icon;
}

/// Result of a QuickAdd save — everything #17's repository insert needs.
@immutable
class NewEntry {
  const NewEntry({
    required this.kind,
    required this.categoryId,
    required this.amount,
    required this.day,
    this.note,
  });

  final EntryKind kind;
  final int categoryId;
  final Money amount;
  final DateTime day;
  final String? note;
}

/// Opens QuickAdd (design §2.2). Cold opens default to Expense/no category;
/// pass the previous save's kind+categoryId to reopen "warm" — rapid second
/// entry is a §2.2 requirement, and the Ledger (#17) owns that memory.
Future<NewEntry?> showQuickAdd(
  BuildContext context, {
  required List<CategoryOption> categories,
  required Currency currency,
  EntryKind initialKind = EntryKind.expense,
  int? initialCategoryId,
  VoidCallback? onManageCategories,
}) => showModalBottomSheet<NewEntry>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => _QuickAddSheet(
    categories: categories,
    currency: currency,
    initialKind: initialKind,
    initialCategoryId: initialCategoryId,
    onManageCategories: onManageCategories,
  ),
);

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({
    required this.categories,
    required this.currency,
    required this.initialKind,
    required this.initialCategoryId,
    required this.onManageCategories,
  });

  final List<CategoryOption> categories;
  final Currency currency;
  final EntryKind initialKind;
  final int? initialCategoryId;
  final VoidCallback? onManageCategories;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.currency);
  late EntryKind _kind = widget.initialKind;
  late int? _categoryId = widget.initialCategoryId;
  DateTime _day = DateTime.now();

  bool _dateStripOpen = false;
  bool _noteActive = false;
  final TextEditingController _note = TextEditingController();
  final FocusNode _noteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      // §2.2: note entry borrows the system keyboard and gives it back on
      // blur — an empty note collapses, a written one stays.
      if (!_noteFocus.hasFocus && _note.text.isEmpty && _noteActive) {
        setState(() => _noteActive = false);
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _pad.money.isPositive && _categoryId != null;

  /// Hardening #20: sheet routes stay hit-testable during the pop
  /// animation, so a fast double-tap on Save would pop the ledger too.
  /// The first pop wins; every later call is a no-op.
  bool _popped = false;

  void _save() {
    if (_popped) return;
    _popped = true;
    final note = _note.text.trim();
    Navigator.pop(
      context,
      NewEntry(
        kind: _kind,
        categoryId: _categoryId!,
        // Money carries its currency: the caller sees a foreign-currency
        // save exactly as typed (E5 §6).
        amount: _pad.money,
        day: _day,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  /// E5 §6: switch the currency this amount is typed in. Base stays the
  /// cold-open default every time (per-entry choice, not a per-device one).
  Future<void> _pickCurrency() async {
    final picked = await showCurrencyChoice(
      context,
      currentCode: _pad.currency.code,
    );
    if (picked != null && mounted) setState(() => _pad.setCurrency(picked));
  }

  @override
  Widget build(BuildContext context) {
    // ~48 % of the screen (§2.2) with a 480 dp floor so the keypad keeps
    // §3 touch-min keys on short screens; keyboard (note only) pushes it
    // up. The budget tracks the system font scale (device feedback
    // 2026-11-04: large fonts made the fixed rows spill Save past the
    // sheet’s bottom — pixel-overflow stripes and a button behind the
    // system nav bar) and is capped at 92 % so the sheet never consumes
    // the whole screen.
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navBar = MediaQuery.viewPaddingOf(context).bottom;
    // Owner pass, 2026-11-06 (demo-entry session): 492fadc cleared the
    // nav bar out of the sheet's paint — Save had been under it — but it
    // took those ~48 dp out of the keypad's slack instead of the budget,
    // so on 3-button devices the pad fell under its own 4×touch-min
    // minimum and `. 0 ⌫` hid behind the extreme-scale scroll hatch:
    // decimals and zeroes were untypeable without discovering an
    // unlabeled scroll. The floor now states the real requirement:
    // fixed chrome (≈340 dp) + keypad minimum (192 dp) + nav bar.
    final need = 560.0 + navBar;
    final height = math.min(
      size.height * 0.92,
      math.max(math.max(480.0, size.height * 0.48), need) *
          math.max(1.0, textScale),
    );

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
          // Save underneath the bar).
          padding: EdgeInsets.fromLTRB(
            Tokens.space4,
            Tokens.space2,
            Tokens.space4,
            Tokens.space4 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: size.width > size.height ? _landscape() : _portrait(),
        ),
      ),
    );
  }

  // ---- sheet pieces ----------------------------------------------------
  //
  // Portrait stacks everything and lets the keypad swallow the slack
  // between amount and chips. Landscape flips the budget: the short
  // screen cannot carry 4×touch-min rows on top of the fields, and the
  // pad clipped mid-row — half a keypad reads as broken (device feedback
  // 2026-11-04 pm). So the pad gets its own right-hand pane and the
  // fields scroll beside it.

  Widget _portrait() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // min-height, not a tight box: the M3 button grows with the
      // font instead of clipping it (device feedback 2026-11-04).
      _kindToggle(),
      const SizedBox(height: Tokens.space2),
      AmountDisplay(pad: _pad, currency: _pad.currency),
      const SizedBox(height: Tokens.space2),
      Expanded(
        // Extreme font scales keep every key tappable: below
        // 4×touch-min the pad holds its minimum and scrolls
        // instead of pushing the rows below it off the sheet.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: SizedBox(
              height: math.max(box.maxHeight, 4 * Tokens.touchMin),
              child: _keypad(),
            ),
          ),
        ),
      ),
      _chips(),
      const SizedBox(height: Tokens.space2),
      _optionalRow(),
      const SizedBox(height: Tokens.space2),
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
              _kindToggle(),
              const SizedBox(height: Tokens.space2),
              AmountDisplay(pad: _pad, currency: _pad.currency),
              const SizedBox(height: Tokens.space2),
              _chips(),
              const SizedBox(height: Tokens.space2),
              _optionalRow(),
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

  Widget _kindToggle() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: SegmentedButton<EntryKind>(
      segments: const [
        ButtonSegment(value: EntryKind.expense, label: Text('Expense')),
        ButtonSegment(value: EntryKind.income, label: Text('Income')),
      ],
      selected: {_kind},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _kind = s.first),
    ),
  );

  Widget _keypad() => Keypad(
    onDigit: (d) => setState(() => _pad.digit(d)),
    onDot: () => setState(_pad.dot),
    onBackspace: () => setState(_pad.back),
    dotEnabled: _pad.currency.minorUnits > 0,
  );

  Widget _chips() => CategoryChips(
    categories: widget.categories,
    selectedId: _categoryId,
    onSelect: (id) => setState(() => _categoryId = id),
    onManage: widget.onManageCategories,
  );

  Widget _optionalRow() => _OptionalRow(
    day: _day,
    currencyCode: _pad.currency.code,
    stripOpen: _dateStripOpen,
    noteActive: _noteActive,
    noteController: _note,
    noteFocus: _noteFocus,
    onPickCurrency: _pickCurrency,
    onToggleDateStrip: () => setState(() => _dateStripOpen = !_dateStripOpen),
    onPickDay: (day) => setState(() {
      _day = day;
      _dateStripOpen = false;
    }),
    onOpenCalendar: _openCalendar,
    onActivateNote: () => setState(() {
      _noteActive = true;
      _dateStripOpen = false;
    }),
  );

  Widget _saveButton() => SizedBox(
    height: Tokens.touchMin,
    child: FilledButton(
      // M3 FilledButton renders its own disabled state (§2.2).
      onPressed: _canSave ? _save : null,
      child: const Text('Save'),
    ),
  );

  Future<void> _openCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = picked);
  }
}

/// §2.2: optional fields behind one row of TextButtons — `Today ▾` reveals an
/// inline strip (Yesterday / Today / Calendar); `Add note` swaps in a 48 dp
/// textfield that borrows the system keyboard until blur.
class _OptionalRow extends StatelessWidget {
  const _OptionalRow({
    required this.day,
    required this.currencyCode,
    required this.stripOpen,
    required this.noteActive,
    required this.noteController,
    required this.noteFocus,
    required this.onPickCurrency,
    required this.onToggleDateStrip,
    required this.onPickDay,
    required this.onOpenCalendar,
    required this.onActivateNote,
  });

  final DateTime day;
  final String currencyCode;
  final bool stripOpen;
  final bool noteActive;
  final TextEditingController noteController;
  final FocusNode noteFocus;
  final VoidCallback onPickCurrency;
  final VoidCallback onToggleDateStrip;
  final ValueChanged<DateTime> onPickDay;
  final VoidCallback onOpenCalendar;
  final VoidCallback onActivateNote;

  @override
  Widget build(BuildContext context) {
    if (noteActive) {
      return SizedBox(
        height: Tokens.touchMin,
        child: TextField(
          controller: noteController,
          focusNode: noteFocus,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
    }

    if (stripOpen) {
      final now = DateTime.now();
      // FittedBox(scaleDown) per §5: at 1.3× text scale three labels exceed
      // a 360 dp sheet, so the strip shrink-wraps proportionally instead of
      // clipping or ellipsizing. (A Flexible/Spacer mix cannot do this —
      // flex children split *all* leftover width, truncating even at 1.0×.)
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () =>
                  onPickDay(DateTime(now.year, now.month, now.day - 1)),
              child: const Text('Yesterday'),
            ),
            TextButton(
              onPressed: () =>
                  onPickDay(DateTime(now.year, now.month, now.day)),
              child: const Text('Today'),
            ),
            TextButton(
              onPressed: onOpenCalendar,
              child: const Text('Calendar…'),
            ),
          ],
        ),
      );
    }

    // Same §5 pattern, but the collapsed pill row keeps both ends pinned.
    // The child must size to its INTRINSIC width (floor: available width):
    // a fixed-width SizedBox reports `available` as its size, FittedBox then
    // computes scale 1.0 and the Row overflows *inside* the boundary.
    // ConstrainedBox + mainAxisSize.min gives spaceBetween the leftover when
    // under available, and lets FittedBox scale the 3.3 px overshoot
    // (1.3× text scale at 360 dp) down by 1%.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: onToggleDateStrip,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(DayLabel.of(day)),
              ),
              // E5 §6: per-entry currency. Middle slot by design — the two
              // pinned ends keep their pixels, only this center appears.
              TextButton.icon(
                key: const Key('currency-button'),
                onPressed: onPickCurrency,
                icon: const Icon(Icons.currency_exchange, size: 18),
                label: Text(currencyCode),
              ),
              TextButton.icon(
                onPressed: onActivateNote,
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: const Text('Add note'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
