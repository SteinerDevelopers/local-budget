import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// One honest passphrase prompt (E5 §3): the sheet is the only place a
/// passphrase is ever typed — backup asks for it twice (type it right, or
/// lose your own file), restore asks once (a wrong one just fails to open).
Future<String?> showPassphraseSheet(
  BuildContext context, {
  required String title,
  bool withConfirm = false,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _PassphraseSheet(title: title, withConfirm: withConfirm),
);

class _PassphraseSheet extends StatefulWidget {
  const _PassphraseSheet({required this.title, required this.withConfirm});

  final String title;
  final bool withConfirm;

  @override
  State<_PassphraseSheet> createState() => _PassphraseSheetState();
}

class _PassphraseSheetState extends State<_PassphraseSheet> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _pass.text;
    if (value.isEmpty) {
      setState(
        () => _error =
            'A backup without a passphrase is just a file '
            'anyone can open.',
      );
      return;
    }
    if (widget.withConfirm && value != _confirm.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    isDense: true,
    errorText: _error,
    suffixIcon: IconButton(
      // One eye for both fields — this sheet has exactly one secret.
      key: const Key('passphrase-visibility'),
      icon: Icon(
        _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: () => setState(() => _visible = !_visible),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.space4,
        Tokens.space4,
        Tokens.space4,
        Tokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Tokens.space4),
          TextField(
            key: const Key('passphrase-field'),
            controller: _pass,
            obscureText: !_visible,
            autocorrect: false,
            decoration: _decoration('Passphrase'),
            onSubmitted: (_) => widget.withConfirm ? null : _submit(),
          ),
          if (widget.withConfirm) ...[
            const SizedBox(height: Tokens.space3),
            TextField(
              key: const Key('passphrase-confirm-field'),
              controller: _confirm,
              obscureText: !_visible,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Repeat passphrase',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          const SizedBox(height: Tokens.space4),
          FilledButton(
            key: const Key('passphrase-next'),
            onPressed: _submit,
            child: const Text('Continue'),
          ),
          const SizedBox(height: Tokens.space2),
        ],
      ),
    );
  }
}
