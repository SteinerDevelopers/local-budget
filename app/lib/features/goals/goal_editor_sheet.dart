// #37 — Goal editor (design e3 §2.4): name, an optional target (a blank
// pad = open-ended, per §2.4's "optional target"), and a note. One sheet
// for create and edit, mirroring the limit editor's keypad grammar.
// Returns true when anything changed so the caller reloads.
import 'dart:math' as math;

import 'package:core/core.dart' show Currency;
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../quickadd/amount_display.dart';
import '../quickadd/amount_pad.dart';
import '../quickadd/keypad.dart';

Future<bool?> showGoalEditor(
  BuildContext context, {
  required LedgerRepository repository,
  Goal? goal,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _GoalEditorSheet(repository: repository, goal: goal),
);

class _GoalEditorSheet extends StatefulWidget {
  const _GoalEditorSheet({required this.repository, this.goal});

  final LedgerRepository repository;
  final Goal? goal;

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.goal?.name ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.goal?.note ?? '',
  );
  Currency? _currency;
  AmountPad? _pad;

  bool get _isEdit => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal != null) {
      _open(Currency.resolve(goal.currencyCode));
    } else {
      // New goals inherit the household's base currency (same fallback
      // chain as the bills tab).
      widget.repository.baseCurrency().then((code) {
        if (mounted) setState(() => _open(Currency.resolve(code ?? 'USD')));
      });
    }
  }

  void _open(Currency currency) {
    final pad = AmountPad(currency: currency);
    // Pre-fill the stored target with its exact digits — no float
    // round-trip, same split the limit editor uses.
    final minor = widget.goal?.targetMinor;
    if (pad.currency.minorUnits <= 0) {
      if (minor != null && minor > 0) {
        for (final d in minor.toString().split('')) {
          pad.digit(d);
        }
      }
    } else if (minor != null && minor > 0) {
      final pow10 = math.pow(10, pad.currency.minorUnits).toInt();
      final whole = minor ~/ pow10;
      final frac = (minor % pow10).toString().padLeft(
        pad.currency.minorUnits,
        '0',
      );
      for (final d in whole.toString().split('')) {
        pad.digit(d);
      }
      final trimmed = frac.replaceFirst(RegExp(r'0+$'), '');
      if (trimmed.isNotEmpty) {
        pad.dot();
        for (final d in trimmed.split('')) {
          pad.digit(d);
        }
      }
    }
    _currency = currency;
    _pad = pad;
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pad = _pad;
    final currency = _currency;
    final name = _name.text.trim();
    if (pad == null || currency == null || name.isEmpty) return;
    final note = _note.text.trim();
    final goal = widget.goal;
    if (goal == null) {
      await widget.repository.addGoal(
        name: name,
        currencyCode: currency.code,
        targetMinor: pad.isEmpty ? null : pad.money.minorUnits,
        note: note.isEmpty ? null : note,
      );
    } else {
      // Value(null) — not plain null — so a cleared pad truly clears a
      // set target back to open-ended, and a cleared note clears the note.
      await widget.repository.updateGoal(
        goal.id,
        name: name,
        targetMinor: Value<int?>(pad.isEmpty ? null : pad.money.minorUnits),
        note: Value(note.isEmpty ? null : note),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // QuickAdd's height grammar (device feedback 2026-11-04 pm): a
    // font-scaled budget capped at 92 % — the old 520 dp floor was taller
    // than a landscape phone, so the pad clipped mid-row there — plus
    // nav-bar clearance the modal deliberately does not inset. The floor
    // must include that nav-bar clearance because it is spent INSIDE the
    // fixed height (bottom padding below); the sibling limit editor proved
    // the bare floor clips `. 0 ⌫` on 3-button phones (owner report
    // 2026-11-06). The name field buys this sheet one extra row over
    // QuickAdd.
    final pad = _pad;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navBar = MediaQuery.viewPaddingOf(context).bottom;
    final need = 600.0 + navBar;
    final height = math.min(
      size.height * 0.92,
      math.max(math.max(520.0, size.height * 0.56), need) * math.max(1.0, textScale),
    );
    return AnimatedPadding(
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
              _dragBar(context),
              const SizedBox(height: Tokens.space2),
              Text(
                _isEdit ? 'Edit goal' : 'New goal',
                style: Tokens.monthTitle(context),
              ),
              const SizedBox(height: Tokens.space3),
              TextField(
                key: const Key('goal-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Tokens.space2),
              TextField(
                key: const Key('goal-note'),
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: Tokens.space2),
              Text(
                'Target — leave blank for an open-ended goal',
                style: Tokens.labelCaps(context),
              ),
              const SizedBox(height: Tokens.space1),
              if (pad == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (size.width > size.height)
                Expanded(child: _landscape(pad))
              else
                ..._portrait(pad),
            ],
          ),
        ),
      ),
    );
  }

  // ---- sheet pieces (same grammar as QuickAdd's sheet) ------------------

  List<Widget> _portrait(AmountPad pad) => [
    Expanded(
      // Below 4×touch-min the pad stops growing and scrolls instead of
      // pushing Save off the sheet — every key stays tappable even at
      // extreme font scales.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: SizedBox(
            height: math.max(box.maxHeight, 4 * Tokens.touchMin),
            child: _keypad(pad),
          ),
        ),
      ),
    ),
    const SizedBox(height: Tokens.space2),
    _saveButton(),
  ];

  Widget _landscape(AmountPad pad) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 3,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountDisplay(pad: pad, currency: _currency!),
              const SizedBox(height: Tokens.space2),
              _saveButton(),
            ],
          ),
        ),
      ),
      const SizedBox(width: Tokens.space2),
      Expanded(flex: 2, child: _keypad(pad)),
    ],
  );

  Widget _keypad(AmountPad pad) => Keypad(
    onDigit: (d) => setState(() => pad.digit(d)),
    onDot: () => setState(pad.dot),
    onBackspace: () => setState(pad.back),
    dotEnabled: _currency!.minorUnits > 0,
  );

  Widget _saveButton() => SizedBox(
    height: Tokens.touchMin,
    child: FilledButton(
      key: const Key('goal-save'),
      onPressed: _name.text.trim().isEmpty ? null : _save,
      child: Text(_isEdit ? 'Save' : 'Create goal'),
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
}
