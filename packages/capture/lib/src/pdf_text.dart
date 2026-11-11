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

import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// Tier-1 alternative for PDFs with a real text layer (e2-capture.md §3,
/// feasibility §2.5). Adapters in the app may delegate to richer extractors;
/// the pure-Dart implementation below covers ordinary generated e-receipts.
abstract interface class PdfText {
  /// Text lines in file order. An empty line is inserted between content
  /// streams so callers can approximate "page 1" (streams ≈ pages in the
  /// generated PDFs receipts actually are — decision 5 imports one document).
  List<String> readTextLayer(Uint8List pdf);
}

/// A scanned PDF becomes an image the Tier-1 [TextExtractor] can read
/// (rendered by pdfium in the app adapter, C5).
abstract interface class TextRenderer {
  /// Page 1 of [pdf] as PNG bytes.
  Future<Uint8List> renderPage1(Uint8List pdf);
}

/// Below this many characters on page 1 the document is treated as scanned
/// (e2-capture.md §3; pinned by test — the review copy depends on it).
const int kTextLayerMinChars = 20;

/// Max pages rendered + OCR'd from one scanned PDF (e11 §2): a 40-page PDF
/// must not hang the phone; the wizard discloses "first N pages" truncation.
const int kRenderedPageCap = 10;

/// Per-page view of a PDF text layer (e11 §2). The default groups
/// [PdfText.readTextLayer]'s flat output at its stream-boundary markers —
/// `SimplePdfText` already walks every content stream, so this is a real
/// multi-page walk, and adapters inherit it with zero churn (Dart's
/// `implements` ignores bodies declared on interface members, hence the
/// extension).
extension PdfTextPages on PdfText {
  /// Lines grouped per page, page order; pages that yielded nothing vanish.
  List<List<String>> readTextLayerPages(Uint8List pdf) {
    final pages = <List<String>>[];
    var cur = <String>[];
    for (final l in readTextLayer(pdf)) {
      if (l.isEmpty) {
        if (cur.isNotEmpty) pages.add(cur);
        cur = <String>[];
      } else {
        cur.add(l);
      }
    }
    if (cur.isNotEmpty) pages.add(cur);
    return pages;
  }
}

/// Multi-page rendering (e11 §2). Default renders page 1 only; an adapter
/// that truly renders several pages declares `renderPages` on its *concrete*
/// class and is called through that type — extension members never dispatch
/// virtually through the interface. Implementations must honor
/// [kRenderedPageCap].
extension TextRendererPages on TextRenderer {
  /// Pages of [pdf] as PNG bytes, page order.
  Future<List<Uint8List>> renderPages(Uint8List pdf) async => [
        await renderPage1(pdf),
      ];
}

/// True when the first page's text layer is rich enough to trust Tier 2.
bool hasTextLayer(List<String> lines) {
  var chars = 0;
  for (final l in lines) {
    if (l.isEmpty) break; // stream boundary = page boundary
    chars += l.trim().length;
  }
  return chars >= kTextLayerMinChars;
}

/// Minimal, dependency-free text-layer reader for the receipts this app
/// ingests: uncompressed *or* Flate-compressed content streams, literal and
/// hex strings, the seven text-showing/positioning operators.
///
/// Deliberate limits (all fail *safe* — no output ⇒ looks scanned ⇒ OCR):
/// CID/Identity-H encoded fonts (custom glyph maps) produce nothing, Type
/// 3/fonts without ToUnicode likewise, and only WinAnsi-ish byte values are
/// interpreted (ASCII is exact; high bytes pass through as latin-1).
class SimplePdfText implements PdfText {
  const SimplePdfText();

  static final RegExp _streamRe =
      RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream', multiLine: true);

  @override
  List<String> readTextLayer(Uint8List pdf) {
    final raw = String.fromCharCodes(pdf); // latin-1 byte view
    final out = <String>[];
    var lastEnd = 0;
    var first = true;
    for (final m in _streamRe.allMatches(raw)) {
      final dict = raw.substring(lastEnd, m.start);
      lastEnd = m.end;
      final flate = dict.contains('/FlateDecode');
      final text = flate ? _inflate(m.group(1)!) : m.group(1)!;
      // Font programs, ToUnicode CMaps and metadata payloads ride the
      // same `stream…endstream` envelope as page content and can contain
      // bytes shaped like text operators; decoding them turns the CMap
      // itself into "text" (field probe on a real statement PDF, 2026-11).
      if (_looksLikeContent(text)) {
        out.addAll(_contentText(text, firstStream: first));
      }
      first = false;
    }
    return out;
  }

  /// A decompressed stream is page content only if it opens text blocks and
  /// shows/positions text; junk streams rarely carry both markers, and one
  /// that slips through still lacks any date+amount shape downstream.
  static bool _looksLikeContent(String s) =>
      s.contains('BT') &&
      RegExp(r'\bTj\b|\bTJ\b|\bTd\b|\bTD\b|\bT\*\b').hasMatch(s);

  static String _inflate(String body) {
    try {
      return String.fromCharCodes(ZLibCodec().decode(_bytesOf(body)));
    } on Object {
      return ''; // undecodable stream: skip, never throw
    }
  }

  static Uint8List _bytesOf(String s) =>
      Uint8List.fromList(s.codeUnits.map((c) => c & 0xFF).toList());

  /// One content stream → lines. New output line on any positioning operator
  /// (`Td TD T* Tm BT`) or the quote operators; strings concatenate with a
  /// boundary rule that never splits digit runs (kerned text).
  static List<String> _contentText(String s, {required bool firstStream}) {
    final lines = <String>[];
    final cur = StringBuffer();
    final tok = RegExp(
      r'\((?:\\(?:[nrtbf()\\]|\d{1,3})|\\.|[^\\()])*\)' // literal string
      r'|\[[^\[\]]*\]' // TJ array
      r'|<[0-9A-Fa-f\s]*>' // hex string
      r'|BT|ET|Td|TD|Tm|T\*|Tj|TJ' // block/position/show operators
      r'''|['"]''', // quote show-and-next-line operators
      multiLine: true,
    );
    const flushers = {'Td', 'TD', 'Tm', 'T*', 'BT', 'ET', "'", '"'};
    void flush() {
      if (cur.isNotEmpty) {
        lines.add(cur.toString());
        cur.clear();
      }
    }

    for (final m in tok.allMatches(s)) {
      final t = m.group(0)!;
      final c0 = t.codeUnitAt(0);
      if (c0 == 0x28) {
        _append(cur, _decodeLiteral(t)); // (
      } else if (c0 == 0x5B) {
        for (final sm in RegExp(
                r'\((?:\\(?:[nrtbf()\\]|\d{1,3})|\\.|[^\\()])*\)|<[0-9A-Fa-f\s]*>')
            .allMatches(t)) {
          final sub = sm.group(0)!;
          _append(
              cur,
              sub.codeUnitAt(0) == 0x28
                  ? _decodeLiteral(sub)
                  : _decodeHex(sub));
        }
      } else if (c0 == 0x3C) {
        _append(cur, _decodeHex(t)); // <
      } else if (flushers.contains(t)) {
        flush();
      } // else: Tj/TJ show in place — nothing to do
    }
    flush();
    if (!firstStream && lines.isNotEmpty) lines.insert(0, '');
    return lines;
  }

  /// Concatenation with the letter↔digit separator guard: kerned text split
  /// across strings rejoins ("TO"+"TAL"), digit runs never get a hole
  /// ("1"+"2.34"), but "TOTAL"+"12.34" still reads as two words.
  static void _append(StringBuffer buf, String add) {
    if (add.isEmpty) return;
    if (buf.isEmpty) {
      buf.write(add);
      return;
    }
    final a = buf.toString().codeUnitAt(buf.length - 1);
    final b = add.codeUnitAt(0);
    final aLetter = (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A);
    final aDigit = a >= 0x30 && a <= 0x39;
    final bLetter = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
    final bDigit = b >= 0x30 && b <= 0x39;
    if ((aLetter && bDigit) || (aDigit && bLetter)) buf.write(' ');
    buf.write(add);
  }

  static String _decodeLiteral(String t) {
    final body = t.substring(1, t.length - 1);
    final out = StringBuffer();
    var i = 0;
    while (i < body.length) {
      final c = body[i];
      if (c == r'\' && i + 1 < body.length) {
        final n = body[i + 1];
        switch (n) {
          case 'n':
            out.write('\n');
            i += 2;
          case 'r':
            out.write('\r');
            i += 2;
          case 't':
            out.write('\t');
            i += 2;
          case 'b':
          case 'f':
            i += 2;
          case r'\':
          case '(':
          case ')':
            out.write(n);
            i += 2;
          default:
            // octal \ddd (up to 3 digits, max \377)
            final m = RegExp(r'\\(\d{1,3})').matchAsPrefix(body, i);
            final oct = m == null ? null : int.tryParse(m.group(1)!, radix: 8);
            if (m != null && oct != null) {
              out.writeCharCode(oct & 0xFF);
              i += m.group(0)!.length;
            } else {
              out.write(n);
              i += 2;
            }
        }
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  static String _decodeHex(String t) {
    final hex = t.substring(1, t.length - 1).replaceAll(RegExp(r'\s'), '');
    final out = StringBuffer();
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.writeCharCode(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out.toString();
  }
}
