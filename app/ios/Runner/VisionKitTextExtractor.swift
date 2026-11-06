// E12 §6 — iOS VisionKit text-extraction seam (design stub).
//
// THIS FILE IS NOT REGISTERED IN project.pbxproj AND THEREFORE NEVER
// COMPILES IN ANY BUILD. It exists so E10 owns the real implementation
// against a written contract (docs/design/e12-ios-visionkit-seam.md).
// This development environment has no macOS/Xcode toolchain; no iOS build
// or test result is claimed by this file, and none should be inferred
// from it. E10's checklist: implement, register with Xcode, verify on a
// physical device, then delete the UnimplementedError bodies.
//
// Contract mirrors Android's ML Kit TextExtractor one-for-one:
//   in  : image bytes (JPEG/HEIC/PNG, <= 8 MB)
//   out : OCR lines in reading order (top-to-bottom, line-grouped)
//   errors: vision_unavailable / vision_no_text / vision_failed

#if canImport(VisionKit) && os(iOS)

import Foundation
import VisionKit

enum VisionOcrError: Error {
  /// Device is below iOS 16 or Vision reports no text capability.
  case unavailable
  /// Analyzer ran and found nothing — maps to the channel error
  /// `vision_no_text`; the capture pipeline shows the honest snack.
  case noText
  /// Underlying VisionKit failure; localizedDescription travels with it.
  case failed(Error)
}

/// E10: implement with
/// `ImageAnalyzer.recommendedAnalyzerSet().analyzer(recognizesText:)` and
/// `analyze(image:types:[.recognizeText],configuration:)`, mapping
/// `VNRecognizedTextObservation.topCandidates(1)` to page lines: group
/// observations by overlapping boundingBox.midY bands, sort lines by
/// descending midY (Vision's origin is bottom-left), fragments by minX,
/// join each line's fragments with single spaces. No permissions; fully
/// on-device.
@available(iOS 16.0, *)
final class VisionKitTextExtractor {
  static let shared = VisionKitTextExtractor()

  /// Channel `localbudget/vision_ocr`, method `extractText`
  /// (args `{"bytes": Data}`; result `[String]`).
  func extractText(bytes: Data) async throws -> [String] {
    // Stub on purpose — see the file header. Do not "make this compile"
    // without the Xcode registration and on-device verification.
    throw VisionOcrError.failed(
      UnimplementedError()
    )
  }
}

#endif  // canImport(VisionKit) && os(iOS)
