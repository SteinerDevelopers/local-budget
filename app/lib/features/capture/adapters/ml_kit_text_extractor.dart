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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart' show OcrLineAssembly, OcrWord;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// On-device OCR adapter (issue #28, design §3 Tier 1): ML Kit's bundled
/// latin recognizer turns one image into the text lines the heuristics read.
/// Nothing is ever uploaded — this is the whole Tier-1 story (decision 8).
///
/// The `TextExtractor` contract says an image that yields nothing returns an
/// empty list — blur and bad light are states, not errors — so every failure
/// path (missing plugin, engine hiccup, unreadable temp file) collapses to
/// `const []` and Review opens with empty fields for typing.
class MlKitTextExtractor implements TextExtractor {
  /// One recognizer per app run: creating it is not free on device and the
  /// flow is strictly one document at a time (decision 5).
  TextRecognizer? _recognizer;

  /// Debug-build trace of the assembled lines the heuristics will read.
  /// Field reports ("the payee came out wrong") become reproducible from
  /// `adb logcat -s flutter:V | grep ocr-lines` instead of guesswork.
  /// Must be debugPrint (stdout → Logcat under tag `flutter`), NOT
  /// `dart:developer log()`: on stock Android the latter goes only to the
  /// Dart VM service, which is unreachable without a workstation attach —
  /// proven on the SL219A test phone (zero `ocr-lines` entries ever
  /// reached Logcat while the recognizer ran). Never compiled into
  /// behavior outside debug builds — document text stays on-device and
  /// off the logs in release, per the Tier-1 privacy story.
  void _dump(List<String> lines) {
    if (!kDebugMode) return;
    debugPrint('[ocr-lines] assemble → ${lines.length} lines');
    for (var i = 0; i < lines.length; i++) {
      debugPrint('[ocr-lines][$i] ${lines[i]}');
    }
  }

  @override
  Future<List<String>> extractText(Uint8List bytes) async {
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File(
        '${dir.path}/ocr-${DateTime.now().microsecondsSinceEpoch}.img',
      );
      await tmp.writeAsBytes(bytes);
      final recognizer = _recognizer ??= TextRecognizer();
      final result = await recognizer.processImage(
        InputImage.fromFilePath(tmp.path),
      );
      // Words → visual lines (§3 v1.1): ML Kit blocks split a receipt's
      // label and amount columns, which hides `TOTAL $42.50` from the
      // anchors; regrouping by vertical center puts them back on one line.
      final words = <OcrWord>[
        for (final block in result.blocks)
          for (final line in block.lines)
            for (final element in line.elements)
              OcrWord(
                text: element.text,
                centerX: element.boundingBox.center.dx,
                centerY: element.boundingBox.center.dy,
                height: element.boundingBox.height,
              ),
      ];
      List<String> lines;
      if (words.isEmpty) {
        // No boxes at all (unexpected engine output): keep the old
        // block→line order rather than return nothing.
        lines = [
          for (final block in result.blocks)
            for (final line in block.lines) line.text,
        ];
      } else {
        lines = OcrLineAssembly.assemble(words);
      }
      _dump(lines);
      return lines;
    } catch (_) {
      return const [];
    } finally {
      if (tmp != null) {
        try {
          await tmp.delete();
        } catch (_) {
          // Temp cleanup is best effort; the OS reclaims the dir eventually.
        }
      }
    }
  }
}
