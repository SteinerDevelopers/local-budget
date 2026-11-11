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
    // Frame rule as QuickAdd (§2.1): 48 % with a 480 dp floor so rows keep
    // full touch height on short screens, capped at 92 %; the body scrolls
    // so even the route's smaller initial frame overflows nothing (device
    // feedback 2026-11-04; CI guard 2026-11-10). The frame now FITS the
    // content instead of scaling with it: only title and subtitle grow
    // with the text scale — the §2.1 rows stay 56 dp by law (FittedBox
    // overflow guard, 2026-11-10). The old `× textScale` grew the whole
    // frame for the text that grew a fraction of it: at 2.0× that was a
    // dead lower half (T2, tablet audit 2026-11-10).
    // Budget: 32 pad + 32 gaps + 24 slack + (28 title + 2×20 subtitle)·
    // scale + 4×56 rows. At 1.0× the §2.1 frame still governs everywhere.
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final content = 88 + 68 * textScale + 4 * 56.0;
    final height = math.min(
      size.height * 0.92,
      math.max(math.max(480.0, size.height * 0.48), content),
    );
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
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              // Stretch to the viewport like the old Spacer did: rows sit
              // top-aligned and the leftover stays empty below them.
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Tokens.space1),
                  // Decision 5, made audible at the front door.
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Tokens.space3),
                  for (final choice in CaptureChoice.values)
                    if (choice == CaptureChoice.screenshot &&
                        !showScreenshotRow)
                      const SizedBox.shrink()
                    else
                      _SourceRow(
                        choice: choice,
                        icon: _icons[choice]!,
                        onTap: () => Navigator.pop(context, choice),
                      ),
                  const SizedBox(height: Tokens.space4),
                ],
              ),
            ),
          ),
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
            Expanded(
              // §5 scaleDown precedent (AmountDisplay): a long label at
              // 2.0× shrank to fit instead of spilling the Row past the
              // sheet ('Recent screenshot' overflowed by 260 px in CI).
              // Row stays 56 dp — scaling the row instead would push the
              // sheet body past its own height.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  choice.label,
                  style: const TextStyle(fontSize: Tokens.bodySize),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
