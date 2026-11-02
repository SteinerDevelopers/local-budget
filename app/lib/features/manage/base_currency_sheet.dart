import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

/// Spec §2.4: a plain picker of `core`'s currency list. Picking is immediate
/// — one tap writes the setting and returns; no confirm dialog (zero-dialog
/// rule, §2.1).
Future<void> showBaseCurrencyPicker(
  BuildContext context, {
  required LedgerRepository repository,
  required String current,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _BaseCurrencySheet(repository: repository, current: current),
);

class _BaseCurrencySheet extends StatelessWidget {
  const _BaseCurrencySheet({required this.repository, required this.current});

  final LedgerRepository repository;
  final String current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Base currency', style: theme.textTheme.titleMedium),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in Currency.known.values)
                ListTile(
                  leading: SizedBox(
                    width: 32,
                    child: Text(
                      c.symbol,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Text(c.displayName),
                  trailing: Text(
                    c.code,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: c.code == current
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  selected: c.code == current,
                  selectedTileColor: theme.colorScheme.secondaryContainer,
                  onTap: () async {
                    await repository.setBaseCurrency(c.code);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
        // §2.4 verbatim note — shown right under the picker, where the
        // decision is made.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'Used for balances display. Existing transactions keep their '
            'own currency.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
