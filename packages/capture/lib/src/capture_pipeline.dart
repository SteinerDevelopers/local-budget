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

import 'interfaces.dart';
import 'merge.dart';
import 'pdf_text.dart';

/// Scan → Review orchestration (e2-capture.md §3).
///
/// The pipeline's *only* output is a [ReceiptDraft] for the review sheet —
/// it never persists anything (never auto-commit, decision 5). Tiers:
/// 1 [TextExtractor] (optional — absent on hosts without OCR),
/// 2 [ReceiptHeuristics] from core (always on),
/// 3 [LlmStructurer] (optional, fill-only merge, zero-cost short-circuit).
class CapturePipeline {
  CapturePipeline({
    required this.currency,
    this.extractor,
    this.structurer,
    DateTime? now,
  }) : heuristics = ReceiptHeuristics(currency: currency, now: now);

  final Currency currency;
  final TextExtractor? extractor;
  final LlmStructurer? structurer;
  final ReceiptHeuristics heuristics;

  /// Photo, camera scan or screenshot: Tier 1 → Tier 2 → optional Tier 3.
  /// Without an extractor this degrades to an empty draft — the review sheet
  /// still opens and the user types everything.
  Future<ReceiptDraft> fromImage(Uint8List bytes) async {
    final ex = extractor;
    if (ex == null) return heuristics.extract(const []);
    final lines = await ex.extractText(bytes);
    return _withOptionalStructuring(bytes, lines);
  }

  /// A PDF with a real text layer skips Tier 1 entirely (its "lines" come
  /// from `PdfText`, C2). [bytes] stay available for a future re-OCR.
  Future<ReceiptDraft> fromTextLines(List<String> lines) =>
      _withOptionalStructuring(null, lines);

  /// PDF ingest decision tree (e2-capture.md §3): trust the text layer when
  /// page 1 has ≥ [kTextLayerMinChars] characters; otherwise render page 1
  /// and OCR it (scanned receipt); with no renderer available, any partial
  /// text found is still better than an empty sheet.
  Future<ReceiptDraft> fromPdf(
    Uint8List bytes, {
    PdfText pdfText = const SimplePdfText(),
    TextRenderer? renderer,
  }) async {
    final lines = pdfText.readTextLayer(bytes);
    if (hasTextLayer(lines)) return _withOptionalStructuring(null, lines);
    final rd = renderer;
    if (rd != null) return fromImage(await rd.renderPage1(bytes));
    return _withOptionalStructuring(
        null, lines.where((l) => l.isNotEmpty).toList());
  }

  Future<ReceiptDraft> _withOptionalStructuring(
      Uint8List? bytes, List<String> lines) async {
    final draft = heuristics.extract(lines);
    final st = structurer;
    if (st == null || !draft.needsStructuring || !st.isAvailable()) {
      return draft; // confident or device-unsupported: zero Tier-3 cost
    }
    final llm = await st.structure(bytes ?? Uint8List(0), lines);
    return mergeDraft(draft, llm);
  }
}

/// Whether Tier 3 could still add anything: any field missing or low.
extension DraftNeeds on ReceiptDraft {
  bool get needsStructuring =>
      needsFill(merchant, merchantConfidence) ||
      needsFill(date, dateConfidence) ||
      needsFill(total, totalConfidence);
}
