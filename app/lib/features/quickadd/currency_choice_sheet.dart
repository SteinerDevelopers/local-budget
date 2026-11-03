import 'package:core/core.dart';
import 'package:flutter/material.dart';

/// E5 §6 entry-side picker: which currency this one amount is typed in.
/// Deliberately NOT the base-currency picker — picking here changes only the
/// entry, never the device setting (decision 6: rows keep their own currency).
Future<Currency?> showCurrencyChoice(
  BuildContext context, {
  required String currentCode,
}) => showModalBottomSheet<Currency>(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _CurrencyChoiceSheet(currentCode: currentCode),
);

class _CurrencyChoiceSheet extends StatelessWidget {
  const _CurrencyChoiceSheet({required this.currentCode});

  final String currentCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codes = Currency.known.keys.toList()..sort();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Entry currency', style: theme.textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final code in codes)
                  ListTile(
                    key: ValueKey('currency-$code'),
                    leading: SizedBox(
                      width: 32,
                      child: Text(
                        Currency.known[code]!.symbol,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(Currency.known[code]!.displayName),
                    trailing: Text(
                      code,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: code == currentCode
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, Currency.known[code]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
