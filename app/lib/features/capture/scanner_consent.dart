import 'package:flutter/material.dart';

import 'capture_intake.dart';

/// #56 — the scanner pre-download consent gate (owner ruling 2026-11-13).
///
/// The GMS document scanner's FIRST use may download Google's scanning
/// component through Google Play services; the plugin exposes no probe, so
/// consent is asked once, at the first camera-rung pick, and remembered.
/// Declining is never a promise of manual typing: the plain-camera rung
/// keeps the bundled on-device OCR (owner copy law: a consent dialog must
/// not overstate the cost of refusal). A dialog dismissed by the system
/// with no answer is treated as DECLINE — no download without a yes.
const String kScannerConsentKey = 'scannerConsent';
const String _consentFast = 'fast';
const String _consentPhoto = 'photo';

/// Resolve consent for a camera pick, mutating [intake.allowScanner] for
/// the pick the caller is about to make. [read]/[write] are the settings
/// rows (kept as closures so this stays UI-testable without a repository).
Future<void> gateScannerConsent(
  BuildContext context,
  CaptureIntake intake, {
  required Future<String?> Function() read,
  required Future<void> Function(String) write,
}) async {
  final stored = await read();
  if (stored == _consentFast || stored == _consentPhoto) {
    intake.allowScanner = stored == _consentFast;
    return;
  }
  if (!context.mounted) {
    // The asking view vanished mid-read: fail closed, ask on the next pick.
    intake.allowScanner = false;
    return;
  }
  final allow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Fast scanning uses Google\u2019s scanner'),
      content: const Text(
        'Fast scanning finds the receipt\u2019s edges for you; its first '
        'use may download Google\u2019s scanning component through Google '
        'Play services. It runs on your device \u2014 your photos are '
        'never sent anywhere.\n\n'
        'Without it, take the photo yourself \u2014 the app still reads '
        'the text on your device.',
      ),
      actions: [
        TextButton(
          key: const Key('scanner-consent-photo'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Take photo'),
        ),
        FilledButton(
          key: const Key('scanner-consent-fast'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Fast scan'),
        ),
      ],
    ),
  );
  final answer = allow ?? false;
  intake.allowScanner = answer;
  // The settings row outlives the sheet (draft bookkeeping doctrine):
  // persist even if this view unmounted while the dialog was open.
  await write(answer ? _consentFast : _consentPhoto);
}
