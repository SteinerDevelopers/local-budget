import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';

import 'capture_intake.dart';

/// External share / open-with ingest (§5, decision 5): the first shared
/// image/PDF goes to Review, the rest get the "one at a time" snackbar.
/// Abstract so the ledger tier tests the flow without the plugin.
abstract interface class ShareIngest {
  /// A share that launched the app (cold start).
  Future<List<CapturePick>> initial();

  /// Shares delivered while the app runs.
  Stream<List<CapturePick>> get stream;
}

/// A Tier-3 on-device structurer view bound to one currency (issue #29).
/// Resolved per capture because the ledger currency is runtime-mutable; the
/// app hands the pipeline a fresh view, never a stale currency.
typedef StructurerFor = LlmStructurer Function(Currency currency);

/// Everything the Ledger needs to run the capture flow (E2 §5). Android's
/// real services (image_picker / ML Kit / SAF — issue #28) get assembled in
/// `main.dart`; tests and goldens inject fakes, which is what keeps every
/// review-sheet test hermetic (§7) — no camera, no OCR engine, no disk
/// outside a temp directory.
///
/// `extractor`/`renderer`/`store`/`shares` are nullable so a build (or test)
/// can run the flow end to end with only the pieces it has: no extractor
/// means Review opens with empty fields, no renderer means a scanned PDF
/// degrades to "no total found", no store means the row saves without an
/// attachment, no shares means the app never listens for share intents.
class CaptureServices {
  const CaptureServices({
    required this.intake,
    this.extractor,
    this.renderer,
    this.store,
    this.shares,
    this.structurerFor,
  });

  final CaptureIntake intake;
  final TextExtractor? extractor;
  final TextRenderer? renderer;
  final AttachmentStore? store;
  final ShareIngest? shares;

  /// Tier-3 fill-only structurer (Gemini Nano where the device offers it);
  /// null means the review draft is exactly what Tier 1–2 saw.
  final StructurerFor? structurerFor;
}
