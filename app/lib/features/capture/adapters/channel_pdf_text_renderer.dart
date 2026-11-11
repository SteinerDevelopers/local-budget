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

import 'package:capture/capture.dart' show TextRenderer, kRenderedPageCap;
import 'package:flutter/services.dart';

/// Rasterizes page 1 of a PDF to PNG (issue #28, design section 3): a
/// scanned PDF has no text layer, so the pipeline hands these pixels to the
/// same OCR the camera path uses -- and the Review strip reuses the bitmap
/// as its thumbnail (section 2.3) without a second render.
///
/// The pixels come from the platform's own `android.graphics.pdf.PdfRenderer`
/// over the `localbudget/capture` channel. Deliberately *not* pdfium: a
/// native-assets pdfium package (pdfrx/pdfium_dart) forces a C toolchain on
/// every build host -- including the headless `flutter test` runners -- and
/// grows the APK with per-ABI binaries, all for one page of one document.
/// PdfRenderer is on every device we ship to, dependency-free, and keeps
/// parsing on device (decision 8).
///
/// Failures throw on purpose: `CapturePipeline.fromPdf` treats a missing
/// renderer as "no text layer, open Review anyway", and the Review strip
/// keeps its icon placeholder -- the honest outcome for a broken PDF.
class ChannelPdfTextRenderer implements TextRenderer {
  static const MethodChannel _channel = MethodChannel('localbudget/capture');

  @override
  Future<Uint8List> renderPage1(Uint8List pdf) async {
    final png = await _channel.invokeMethod<Uint8List>('renderPdfFirstPage', {
      'pdf': pdf,
    });
    if (png == null) throw const FormatException('pdf page 1 not renderable');
    return png;
  }

  /// E11 §2 — scanned-statement intake renders the first
  /// [kRenderedPageCap] pages, no more. A concrete method (not the
  /// `TextRendererPages` extension): the extension never dispatches through
  /// the [TextRenderer] interface, so the multi-page path is handed to the
  /// wizard as a tear-off of this exact method (`scannedPdfPages`). The
  /// platform caps too; the `.take` here keeps the contract honest even if
  /// a device returns more.
  Future<List<Uint8List>> renderPages(Uint8List pdf) async {
    // The codec hands a Kotlin List<ByteArray> back as List<Object?>; a
    // direct List<Uint8List> cast would throw on every successful read.
    final pages = await _channel.invokeMethod<List<Object?>>('renderPdfPages', {
      'pdf': pdf,
      'maxPages': kRenderedPageCap,
    });
    final pngs = pages?.whereType<Uint8List>().toList() ?? const <Uint8List>[];
    if (pngs.isEmpty) throw const FormatException('pdf not renderable');
    return pngs.take(kRenderedPageCap).toList();
  }
}
