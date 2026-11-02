import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// A month with zero transactions still shows the month header and balance
/// strip (0.00 everywhere); this is the body underneath (design §2.1:
/// "empty month = header + strip + centered hint").
class EmptyMonth extends StatelessWidget {
  const EmptyMonth({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: Tokens.space3),
          Text('No transactions yet', style: Tokens.body(context)),
          const SizedBox(height: Tokens.space1),
          Text('Tap + to add your first one', style: Tokens.labelCaps(context)),
        ],
      ),
    );
  }
}
