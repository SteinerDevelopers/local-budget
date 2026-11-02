import 'dart:typed_data';

import 'package:core/core.dart';

/// Tier 1 — turn image bytes into OCR-ish text lines, top-to-bottom order.
///
/// The production adapter wraps ML Kit text recognition (bundled model);
/// a scanned-PDF page rendered by pdfium feeds the same interface. Failure
/// is a *state*, not an error: an adapter that cannot read anything returns
/// an empty list and the review sheet handles it.
abstract interface class TextExtractor {
  Future<List<String>> extractText(Uint8List imageBytes);
}

/// Tier 3 — optional on-device structuring (Gemini Nano via ML Kit GenAI).
///
/// [isAvailable] must be checked before [structure]; absence is a normal
/// device state, never an error (decision 10: zero AI UI, zero AI promise).
/// The structurer's output is *merged* under the fill-only rule (see
/// `mergeDraft`), never trusted outright.
abstract interface class LlmStructurer {
  bool isAvailable();

  /// Returns a draft for the same image/lines, or null when it structured
  /// nothing.
  Future<ReceiptDraft?> structure(Uint8List imageBytes, List<String> ocrLines);
}
