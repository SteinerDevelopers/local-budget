import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ledger/day_label.dart';
import '../ledger/view_models.dart';
import 'amount_pad.dart';
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

  void _save() {
    final note = _note.text.trim();
    Navigator.pop(
      context,
      NewEntry(
        kind: _kind,
        categoryId: _categoryId!,
        amount: _pad.money,
        day: _day,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ~48 % of the screen (§2.2) with a 480 dp floor so the keypad keeps
    // §3 touch-min keys on short screens; keyboard (note only) pushes it up.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = math.max(480.0, screenHeight * 0.48);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space4,
            Tokens.space2,
            Tokens.space4,
            Tokens.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: SegmentedButton<EntryKind>(
                  segments: const [
                    ButtonSegment(
                      value: EntryKind.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment(
                      value: EntryKind.income,
                      label: Text('Income'),
                    ),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              ),
              const SizedBox(height: Tokens.space2),
              _AmountDisplay(pad: _pad, currency: widget.currency),
              const SizedBox(height: Tokens.space2),
              Expanded(
                child: Keypad(
                  onDigit: (d) => setState(() => _pad.digit(d)),
                  onDot: () => setState(_pad.dot),
                  onBackspace: () => setState(_pad.back),
                  dotEnabled: widget.currency.minorUnits > 0,
                ),
              ),
              _CategoryChips(
                categories: widget.categories,
                selectedId: _categoryId,
                onSelect: (id) => setState(() => _categoryId = id),
                onManage: widget.onManageCategories,
              ),
              const SizedBox(height: Tokens.space2),
              _OptionalRow(
                day: _day,
                stripOpen: _dateStripOpen,
                noteActive: _noteActive,
                noteController: _note,
                noteFocus: _noteFocus,
                onToggleDateStrip: () =>
                    setState(() => _dateStripOpen = !_dateStripOpen),
                onPickDay: (day) => setState(() {
                  _day = day;
                  _dateStripOpen = false;
                }),
                onOpenCalendar: _openCalendar,
                onActivateNote: () => setState(() {
                  _noteActive = true;
                  _dateStripOpen = false;
                }),
              ),
              const SizedBox(height: Tokens.space2),
              SizedBox(
                height: Tokens.touchMin,
                child: FilledButton(
                  // M3 FilledButton renders its own disabled state (§2.2).
                  onPressed: _canSave ? _save : null,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

/// §2.2 item 2: right-aligned 40 pt tabular value, leading symbol 24 pt
/// onSurfaceVariant, `0` dimmed until the first digit.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.pad, required this.currency});

  final AmountPad pad;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // §5: the hero is the one amount that shrink-wraps under text scale —
    // FittedBox scaleDown keeps long amounts readable instead of clipped.
    return Semantics(
      label: 'Amount ${pad.display}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currency.symbol,
              style: TextStyle(fontSize: 24, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: Tokens.space2),
            Text(
              pad.display,
              key: const Key('amount-value'),
              style: Tokens.amount(context, size: Tokens.amountHeroSize)
                  .copyWith(
                    color: pad.isPlaceholder
                        ? scheme.outline
                        : scheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.2 item 4: single scrolling FilterChip row, `⚙︎` chip last.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onManage,
  });

  final List<CategoryOption> categories;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        // Test handle: the Manage chip sits at the end of a row that can
        // overflow with many categories (#18).
        key: const Key('chip-row'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: Tokens.space2),
              child: FilterChip(
                selected: c.id == selectedId,
                onSelected: (_) => onSelect(c.id),
                avatar: Icon(c.icon, size: 18),
                label: Text(c.name),
              ),
            ),
          if (onManage != null)
            ActionChip(
              avatar: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Manage'),
              // §2.4: jump to Manage. The sheet closes first — its chips are
              // an open-time snapshot anyway, so the next FAB re-reads.
              onPressed: () {
                Navigator.of(context).pop();
                onManage!();
              },
            ),
        ],
      ),
    );
  }
}

/// §2.2: optional fields behind one row of TextButtons — `Today ▾` reveals an
/// inline strip (Yesterday / Today / Calendar); `Add note` swaps in a 48 dp
/// textfield that borrows the system keyboard until blur.
class _OptionalRow extends StatelessWidget {
  const _OptionalRow({
    required this.day,
    required this.stripOpen,
    required this.noteActive,
    required this.noteController,
    required this.noteFocus,
    required this.onToggleDateStrip,
    required this.onPickDay,
    required this.onOpenCalendar,
    required this.onActivateNote,
  });

  final DateTime day;
  final bool stripOpen;
  final bool noteActive;
  final TextEditingController noteController;
  final FocusNode noteFocus;
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
