/// E2 capture pipeline — tiers 1–3 orchestration (docs/design/e2-capture.md).
///
/// Pure Dart: everything here runs (and is tested) without Flutter, plugins
/// or a device. Platform adapters (ML Kit, image_picker, pdfrx) implement the
/// interfaces below in the app layer; tests use fakes.
library;

export 'src/capture_pipeline.dart';
export 'src/interfaces.dart';
export 'src/merge.dart';
