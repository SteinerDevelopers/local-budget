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

import 'interfaces.dart';
import 'pdf_text.dart';

/// Outcome of reading one bill/statement document (e11 §2).
final class DocumentRead {
  const DocumentRead({
    required this.lines,
    required this.pagesRead,
    required this.truncated,
  });

  /// Every readable line in file order — blank lines already dropped.
  final List<String> lines;

  /// Pages actually looked at (1 for an image).
  final int pagesRead;

  /// Page count hit [kRenderedPageCap], so later pages were *not* read —
  /// the wizard must disclose this next to the preview (e11 §2 revision).
  final bool truncated;

  bool get isEmpty => lines.isEmpty;
}

/// Turns document bytes into lines for [DocumentRouter] (e11 §1–§2):
/// images go straight to the text extractor; PDFs trust their text layer,
/// and a *scanned* PDF (page 1 below [kTextLayerMinChars] characters) is
/// rendered page-by-page and OCR'd — capped at [kRenderedPageCap] pages.
///
/// Deliberately separate from `CapturePipeline` (E2, receipt-first, page 1
/// only): this is the bill/statement intake, and it never builds a draft —
/// routing and drafting belong to [DocumentRouter]/`BillDraft` and the
/// statement wizard, so one document can only ever take one path.
///
/// Every failure mode returns null — no extractor, no renderer, a throw
/// mid-render, or a document that yields zero lines. Callers show the
/// "couldn't read text" pointer, never a stack trace (decision 8).
class DocumentExtractor {
  const DocumentExtractor({
    required this.extractor,
    this.renderer,
    this.scannedPdfPages,
    this.pdfText = const SimplePdfText(),
  });

  /// OCR for camera/photo images and rendered pages; null on hosts without
  /// an OCR adapter (then only born-digital PDFs read).
  final TextExtractor? extractor;

  /// Single-page rasterizer — the fallback when [scannedPdfPages] is absent
  /// (an older adapter still reads page 1 of a scanned PDF, honestly).
  final TextRenderer? renderer;

  /// Multi-page rasterizer honoring [kRenderedPageCap]; the app wires the
  /// concrete channel adapter's method here (extension members never
  /// dispatch virtually through [TextRenderer]).
  final Future<List<Uint8List>> Function(Uint8List pdf)? scannedPdfPages;

  final PdfText pdfText;

  /// Camera or gallery image → OCR lines.
  Future<DocumentRead?> fromImage(Uint8List bytes) async {
    final ex = extractor;
    if (ex == null) return null;
    final List<String> raw;
    try {
      raw = await ex.extractText(bytes);
    } on Object {
      return null;
    }
    final lines = _nonBlank(raw);
    if (lines.isEmpty) return null;
    return DocumentRead(lines: lines, pagesRead: 1, truncated: false);
  }

  /// PDF → text-layer lines, or render+OCR for a scanned one (e11 §2).
  Future<DocumentRead?> fromPdf(Uint8List bytes) async {
    List<List<String>> pages;
    try {
      pages = pdfText.readTextLayerPages(bytes);
    } on Object {
      pages = const [];
    }
    if (pages.isNotEmpty && _pageChars(pages.first) >= kTextLayerMinChars) {
      // Born-digital: the whole text layer is readable and cheap to take.
      final lines = _nonBlank([for (final p in pages) ...p]);
      return lines.isEmpty
          ? null
          : DocumentRead(
              lines: lines,
              pagesRead: pages.length,
              truncated: false,
            );
    }
    // Scanned (or a text layer we cannot decode) — render + OCR, capped.
    final ex = extractor;
    if (ex == null) {
      final flat = _nonBlank([for (final p in pages) ...p]);
      return flat.isEmpty
          ? null
          : DocumentRead(
              lines: flat,
              pagesRead: pages.length,
              truncated: false,
            );
    }
    List<Uint8List> images;
    final multi = scannedPdfPages;
    try {
      if (multi != null) {
        images = await multi(bytes);
      } else if (renderer != null) {
        images = [await renderer!.renderPage1(bytes)];
      } else {
        images = const [];
      }
    } on Object {
      return null; // a broken PDF is the same honest "couldn't read" state
    }
    final lines = <String>[];
    var pagesRead = 0;
    for (final img in images.take(kRenderedPageCap)) {
      try {
        lines.addAll(_nonBlank(await ex.extractText(img)));
      } on Object {
        // One unreadable page must not sink the document; keep what we have.
      }
      pagesRead++;
    }
    if (lines.isEmpty) return null;
    return DocumentRead(
      lines: lines,
      pagesRead: pagesRead,
      truncated: pagesRead >= kRenderedPageCap,
    );
  }

  static List<String> _nonBlank(List<String> lines) => [
        for (final l in lines)
          if (l.trim().isNotEmpty) l
      ];

  static int _pageChars(List<String> page) {
    var n = 0;
    for (final l in page) {
      n += l.trim().length;
    }
    return n;
  }
}
