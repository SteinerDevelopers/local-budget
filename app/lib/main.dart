import 'dart:io' show Directory, Platform;

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'design/theme.dart';
import 'features/capture/android_capture_intake.dart';
import 'features/capture/adapters/channel_pdf_text_renderer.dart';
import 'features/capture/adapters/gemini_nano_structurer.dart';
import 'features/capture/adapters/ml_kit_text_extractor.dart';

import 'features/capture/capture_services.dart';
import 'features/ledger/ledger_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One SQLite file in the app's private directory — nothing leaves the
  // device (decision 8: zero collection).
  final dir = await getApplicationDocumentsDirectory();
  final repository = LedgerRepository(
    AppDatabase.openFile('${dir.path}/localbudget.sqlite'),
  );
  // First launch seeds the Cash account + default categories; idempotent.
  await repository.ensureDefaults();
  runApp(LocalBudgetApp(repository: repository, capture: _androidCapture(dir)));
}

/// Real capture services on Android (issue #28): scanner/picker/SAF intake,
/// on-device ML Kit OCR, the platform PdfRenderer page rasterizer, the
/// and the share/open-with ingest. Constructors arm nothing eagerly — no
/// model loads until a capture actually runs. Every other build (iOS until
/// E5, unit/golden tiers inject their own fakes) passes null, and the
/// capture FAB then explains instead of dead-ending (§2.1).
CaptureServices? _androidCapture(Directory docsDir) {
  if (!Platform.isAndroid) return null;
  return CaptureServices(
    intake: AndroidCaptureIntake(),
    extractor: MlKitTextExtractor(),
    renderer: ChannelPdfTextRenderer(),
    store: AttachmentStore(docsDir),
    shares: PluginShareIngest(),
    // Tier 3 (issue #29): one fire-and-forget availability probe at startup;
    // absent AICore means false and the pipeline behaves exactly like E1.
    structurerFor: GeminiNanoStructurer().forCurrency,
  );
}

class LocalBudgetApp extends StatelessWidget {
  /// [theme]/[darkTheme]/[themeMode] exist for the §6 golden harness (CI
  /// injects a font-pinned text theme); the app itself runs on AppTheme.
  /// [capture] is injected by tests/goldens with fakes; `main()` wires the
  /// real Android services (null → the capture FAB explains).
  const LocalBudgetApp({
    super.key,
    required this.repository,
    this.capture,
    this.theme,
    this.darkTheme,
    this.themeMode,
  });

  final LedgerRepository repository;
  final CaptureServices? capture;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      theme: theme ?? AppTheme.light(),
      darkTheme: darkTheme ?? AppTheme.dark(),
      themeMode: themeMode,
      home: LedgerScreen(repository: repository, capture: capture),
    );
  }
}
