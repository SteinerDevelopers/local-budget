// Owner IA pass, 2026-11-05 (second cut): the Receipts and Bills panels add
// through the SAME affordance — a quiet text-icon bar under the list, primary
// on the left, the document scanner on its right. It replaces the Receipts
// FABs so no panel on the home screen parks its add in a different corner.
// The halves are bounded and scale down rather than overflow on narrow
// phones (320 dp is a phone, not a torture test).
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The standard home-panel add bar. `secondary` (usually the document
/// scanner) is *hidden*, never disabled, when a surface can't offer it —
/// the same no-dead-end rule the Bills tab shipped with.
class PanelAddBar extends StatelessWidget {
  const PanelAddBar({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space2),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: primary,
              ),
            ),
            if (secondary != null)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: secondary!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
