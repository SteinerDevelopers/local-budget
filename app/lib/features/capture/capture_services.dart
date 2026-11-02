import 'package:capture/capture.dart';
import 'package:data/data.dart';

import 'capture_intake.dart';

/// Everything the Ledger needs to run the capture flow (E2 §5). Android's
/// real services (image_picker / ML Kit / SAF — issue #28) get assembled in
/// `main.dart`; tests and goldens inject fakes, which is what keeps every
/// review-sheet test hermetic (§7) — no camera, no OCR engine, no disk
/// outside a temp directory.
///
/// `extractor`/`store` are nullable so a build (or test) can run the flow
/// end to end with only the pieces it has: no extractor means Review opens
/// with empty fields, no store means the row saves without an attachment.
class CaptureServices {
  const CaptureServices({required this.intake, this.extractor, this.store});

  final CaptureIntake intake;
  final TextExtractor? extractor;
  final AttachmentStore? store;
}
