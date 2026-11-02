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
    final pad = _pad;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.max(520.0, MediaQuery.sizeOf(context).height * 0.6),
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
              else ...[
                AmountDisplay(pad: pad, currency: _currency!),
                Expanded(
                  child: Keypad(
                    onDigit: (d) => setState(() => pad.digit(d)),
                    onDot: () => setState(pad.dot),
                    onBackspace: () => setState(pad.back),
                    dotEnabled: _currency!.minorUnits > 0,
                  ),
                ),
                const SizedBox(height: Tokens.space2),
                FilledButton(
                  key: const Key('goal-save'),
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                  child: Text(_isEdit ? 'Save' : 'Create goal'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
