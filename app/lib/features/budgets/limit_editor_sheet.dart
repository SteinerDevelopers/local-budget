import 'dart:math' as math;

import 'package:budget/budget.dart' show BudgetPeriodType;
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import '../quickadd/amount_display.dart';
import '../quickadd/amount_pad.dart';
import '../quickadd/category_chips.dart';
import '../quickadd/keypad.dart';
import '../quickadd/quick_add_sheet.dart' show CategoryOption;
import 'budgets_service.dart';

/// Limit editor (design e3 §2.2): the QuickAdd keypad reused for limits.
/// One sheet for all three modes — set the overall target, edit an existing
/// row (with delete), or add a budget for an unbudgeted category.
/// Returns true when anything changed so the caller reloads.
Future<bool?> showLimitEditor(
  BuildContext context, {
  required LedgerRepository repository,
  required BudgetsSnapshot snapshot,
  required int monthIndex,
  BudgetLine? line,
  bool overall = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _LimitEditorSheet(
    repository: repository,
    snapshot: snapshot,
    line: line,
    overall: overall,
  ),
);

class _LimitEditorSheet extends StatefulWidget {
  const _LimitEditorSheet({
    required this.repository,
    required this.snapshot,
    required this.line,
    required this.overall,
  });

  final LedgerRepository repository;
  final BudgetsSnapshot snapshot;
  final BudgetLine? line;
  final bool overall;

  @override
  State<_LimitEditorSheet> createState() => _LimitEditorSheetState();
}

class _LimitEditorSheetState extends State<_LimitEditorSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.snapshot.currency);
  late BudgetPeriodType _type = widget.line == null
      ? BudgetPeriodType.monthly
      : BudgetPeriodType.fromStorage(widget.line!.row.periodType);
  int? _categoryId; // only for add mode

  bool get _isAdd => !widget.overall && widget.line == null;

  @override
  void initState() {
    super.initState();
    final row = widget.line?.row;
    if (row != null) {
      // Pre-fill with the stored digits (no float round-trip: minor units
      // split into int/fraction parts, fraction trimmed of trailing zeros).
      final minor = row.limitMinor;
      final pow10 = _pow10(widget.snapshot.currency.minorUnits);
      final whole = minor ~/ pow10;
      final frac = minor % pow10;
      for (final d in whole.toString().split('')) {
        _pad.digit(d);
      }
      if (frac != 0) {
        _pad.dot();
        final fracText = frac.toString().padLeft(
          widget.snapshot.currency.minorUnits,
          '0',
        );
        for (final d in fracText.replaceFirst(RegExp(r'0+$'), '').split('')) {
          _pad.digit(d);
        }
      }
    }
  }

  static int _pow10(int n) {
    var p = 1;
    for (var i = 0; i < n; i++) {
      p *= 10;
    }
    return p;
  }

  bool get _canSave =>
      _pad.money.isPositive && (!_isAdd || _categoryId != null);

  Future<void> _save() async {
    final categoryId = widget.overall
        ? null
        : widget.line?.row.categoryId ?? _categoryId;
    if (categoryId == null && !widget.overall) return; // #isAdd guard
    await widget.repository.setBudget(
      categoryId: categoryId,
      yearMonth: widget.snapshot.yearMonth,
      limitMinor: _pad.money.minorUnits,
      currencyCode: widget.snapshot.currency.code,
      periodType: _type.storageKey,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final row = widget.line?.row;
    if (row == null) return;
    await widget.repository.deleteBudget(row.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.snapshot.currency;
    final title = widget.overall
        ? 'Monthly target'
        : widget.line == null
        ? 'New budget'
        : 'Edit budget';
    // QuickAdd's height grammar (device feedback 2026-11-04 pm): a
    // font-scaled budget capped at 92 % and nav-bar clearance the modal
    // deliberately does not inset; landscape gives the pad its own pane
    // because the short screen cannot stack it under the fields.
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = math.min(
      size.height * 0.92,
      math.max(480.0, size.height * 0.52) * math.max(1.0, textScale),
    );
    return AnimatedPadding(
      // No text fields here, but keep the same keyboard-proofing grammar as
      // QuickAdd in case the sheet grows one later.
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Padding(
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
              Text(title, style: Tokens.monthTitle(context)),
              const SizedBox(height: Tokens.space3),
              if (_isAdd)
                CategoryChips(
                  categories: [
                    for (final c in widget.snapshot.unbudgetedCategories)
                      CategoryOption(
                        c.id,
                        c.name,
                        ManageIcons.of(c.icon, c.name),
                      ),
                  ],
                  selectedId: _categoryId,
                  onSelect: (id) => setState(() => _categoryId = id),
                  onManage: null,
                )
              else if (widget.line != null)
                _FixedCategory(line: widget.line!),
              if (!widget.overall) ...[
                const SizedBox(height: Tokens.space2),
                SizedBox(
                  height: 40,
                  child: SegmentedButton<BudgetPeriodType>(
                    segments: const [
                      ButtonSegment(
                        value: BudgetPeriodType.monthly,
                        label: Text('Monthly'),
                      ),
                      ButtonSegment(
                        value: BudgetPeriodType.weekly,
                        label: Text('Weekly'),
                      ),
                      ButtonSegment(
                        value: BudgetPeriodType.yearly,
                        label: Text('Yearly'),
                      ),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                ),
              ],
              const SizedBox(height: Tokens.space2),
              AmountDisplay(pad: _pad, currency: currency),
              Expanded(
                child: size.width > size.height
                    ? _landscape()
                    : _portraitKeypad(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portraitKeypad() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Below 4×touch-min the pad stops growing and scrolls instead of
      // pushing the action row off the sheet (same as QuickAdd).
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: SizedBox(
              height: math.max(box.maxHeight, 4 * Tokens.touchMin),
              child: _keypad(),
            ),
          ),
        ),
      ),
      const SizedBox(height: Tokens.space2),
      _actionsRow(),
    ],
  );

  Widget _landscape() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(flex: 3, child: SingleChildScrollView(child: _actionsRow())),
      const SizedBox(width: Tokens.space2),
      Expanded(flex: 2, child: _keypad()),
    ],
  );

  Widget _keypad() => Keypad(
    onDigit: (d) => setState(() => _pad.digit(d)),
    onDot: () => setState(_pad.dot),
    onBackspace: () => setState(_pad.back),
    dotEnabled: widget.snapshot.currency.minorUnits > 0,
  );

  Widget _actionsRow() => Row(
    children: [
      if (widget.line != null)
        TextButton(
          key: const Key('limit-delete'),
          onPressed: _delete,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      const Spacer(),
      FilledButton(
        key: const Key('limit-save'),
        onPressed: _canSave ? _save : null,
        child: const Text('Save'),
      ),
    ],
  );
}

/// Edit mode names the category with a static chip — the chip row is for
/// picking, not a label (§2.2: never offer a duplicate for the same
/// category/period).
class _FixedCategory extends StatelessWidget {
  const _FixedCategory({required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('limit-category'),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: Tokens.space1,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ManageIcons.of(line.iconKey, line.name),
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Tokens.space1),
            Text(line.name, style: Tokens.body(context)),
          ],
        ),
      ),
    );
  }
}
