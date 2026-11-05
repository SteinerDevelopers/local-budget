import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'capture_intake.dart';

/// E2 §2.1 — the capture source sheet. Same 48 % frame rules as QuickAdd;
/// four full-width rows, one row per tap, sheet closes as the picker opens.
/// E11 §5 reuses it without the screenshot row and with document wording.
Future<CaptureChoice?> showCaptureSourceSheet(
  BuildContext context, {
  required bool showScreenshotRow,
  String title = 'Add from receipt',
  String subtitle =
      'One receipt at a time — you review before it\u2019s saved.',
}) => showModalBottomSheet<CaptureChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => CaptureSourceSheet(
    showScreenshotRow: showScreenshotRow,
    title: title,
    subtitle: subtitle,
  ),
);

class CaptureSourceSheet extends StatelessWidget {
  const CaptureSourceSheet({
    super.key,
    required this.showScreenshotRow,
    this.title = 'Add from receipt',
    this.subtitle =
        'One receipt at a time — you review before it\u2019s saved.',
  });

  final bool showScreenshotRow;
  final String title;
  final String subtitle;

  static const _icons = <CaptureChoice, IconData>{
    CaptureChoice.camera: Icons.photo_camera_outlined,
    CaptureChoice.photos: Icons.photo_library_outlined,
    CaptureChoice.pdf: Icons.picture_as_pdf_outlined,
    CaptureChoice.screenshot: Icons.screenshot_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // Same frame rule as QuickAdd (§2.1): 48 % with a 480 dp floor so rows
    // keep full touch height on short screens.
    final height = math.max(480.0, MediaQuery.sizeOf(context).height * 0.48);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space4,
          Tokens.space4,
          Tokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: Tokens.space1),
            // Decision 5, made audible at the front door.
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Tokens.space3),
            for (final choice in CaptureChoice.values)
              if (choice == CaptureChoice.screenshot && !showScreenshotRow)
                const SizedBox.shrink()
              else
                _SourceRow(
                  choice: choice,
                  icon: _icons[choice]!,
                  onTap: () => Navigator.pop(context, choice),
                ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.choice,
    required this.icon,
    required this.onTap,
  });

  final CaptureChoice choice;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      // §2.1: 56 dp rows — the tap target is the whole row.
      height: 56,
      child: InkWell(
        key: Key('capture-${choice.name}'),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: Tokens.space4),
            Text(
              choice.label,
              style: const TextStyle(fontSize: Tokens.bodySize),
            ),
          ],
        ),
      ),
    );
  }
}
