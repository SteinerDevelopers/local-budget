// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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
