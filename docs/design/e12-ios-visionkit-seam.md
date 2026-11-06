# E12 §6 — iOS VisionKit text-extraction seam (design only)

Status: **design + build-gated stub. Nothing here is built or tested in this
environment — there is no macOS/Xcode toolchain, and claiming otherwise would
fail the project's truthfulness bar.** E10 owns the implementation, the Xcode
registration, and the on-device verification.

## Why a seam, not a fork

The whole document pipeline speaks one interface
(`packages/capture/lib/src/interfaces.dart`):

```dart
abstract interface class TextExtractor {
  Future<List<String>> extractText(Uint8List imageBytes);
}
```

Everything downstream — router, statement/item parsers, preview, dedupe,
commit — is platform-blind. Android reaches ML Kit (`TextRecognizer` from
`google_mlkit_text_recognition`) behind an implementation of that interface.
iOS parity therefore means exactly one thing: **a second implementation of
`TextExtractor` whose native side is VisionKit `ImageAnalyzer`.** No parser,
wizard, or storage change is involved.

## Channel contract (proposed)

New lightweight method channel, named after the feature, one method:

| item | value |
| --- | --- |
| channel | `localbudget/vision_ocr` |
| method | `extractText` |
| args | `{ "bytes": <image bytes as Uint8List> }` (JPEG/HEIC/PNG; ≤ 8 MB) |
| ok | `List<String>` — OCR lines, reading order (top→bottom, line-grouped) |
| errors | `vision_unavailable` (iOS < 16), `vision_no_text`, `vision_failed` (underlying error localizedDescription passed as message) |

Semantics identical to the Android extractor: lines as spoken by the page,
empty-not-null for blank pages is *not* allowed — `vision_no_text` is the
ErrorChannel signal the capture pipeline already maps to the honest
"couldn't read" snack.

### Native notes for E10

- `ImageAnalyzer.recommendedAnalyzerSet()` → `recognizesText`; run
  `analyze(image:types:[.recognizeText],configuration:)` with
  `.highPrecision`? No — default accuracy first; precision is an E10 tuning
  decision, not this contract.
- Result mapping: each `VNRecognizedTextObservation.topCandidates(1)`; group
  observations into lines by overlapping `boundingBox.midY` bands, sort
  lines by descending midY (Vision's origin is bottom-left), in-line
  fragments by minX. Join with a single space. This line model is what the
  statement parser's "wrapped description" and item-block rules expect.
- `supportedInterfaceOrientations` and `requiresLowAccuracyMode` do not apply
  off-camera; no permission is requested — VisionKit text recognition runs
  fully on-device with **no new permission** (photo picking stays exactly
  the PHPicker/`openDocument` path already scaffolded).
- PDFs: VisionKit analyzes images only. PDF intake stays on the existing
  `pdf_text` path; a PDFKit-render → VisionKit fallback is a possible E10
  follow-up, deliberately not part of this contract.
- Thread/heap: analyzer calls are async/await; bytes cross once as
  FlutterStandardTypedData. No background mode, no network — "on your
  device" stays literally true.

## Dart sketch (E10 wires it in)

```dart
class VisionKitTextExtractor implements TextExtractor {
  const VisionKitTextExtractor();
  static const _ch = MethodChannel('localbudget/vision_ocr');
  @override
  Future<List<String>> extractText(Uint8List bytes) async =>
      (await _ch.invokeMethod<List<Object?>>('extractText', {'bytes': bytes}))!
          .cast<String>();
}
```

Selection stays where CaptureServices already selects today (per-platform
constructor injection); nothing new is exported publicly.

## What landed in-repo with this note

- `app/ios/Runner/VisionKitTextExtractor.swift` — protocol sketch and error
  enum behind `#if canImport(VisionKit) && os(iOS)`, throwing
  `UnimplementedError` bodies. **It is deliberately not referenced by
  `project.pbxproj`, so it never compiles in any build until E10 registers
  it.** That is what "build-gated stub" means here: the file states the
  contract; the build proves nothing, and no build is claimed.
- No Dart behavior changed; no plugin added; no permission keys touched.
