import 'dart:io';
import 'dart:typed_data';

import 'package:capture/capture.dart' show TextExtractor;
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
      // blocks → lines keeps the top-to-bottom order §3's heuristics assume.
      return [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
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
