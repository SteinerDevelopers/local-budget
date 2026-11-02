import 'dart:io' show Directory, Platform;

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'design/theme.dart';
import 'features/bills/bill_notifier.dart';
import 'features/budgets/budgets_sheet.dart';
import 'features/capture/android_capture_intake.dart';
import 'features/capture/adapters/channel_pdf_text_renderer.dart';
import 'features/capture/adapters/gemini_nano_structurer.dart';
import 'features/capture/adapters/ml_kit_text_extractor.dart';

import 'features/capture/capture_services.dart';
import 'features/ledger/ledger_screen.dart';

/// The navigator notification taps resolve against (§5: tap opens the bill).
final appNavigatorKey = GlobalKey<NavigatorState>();

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
  // Bill reminders: time zone + channel init (inert where unavailable, §5).
  await BillNotifier.bootstrap();
  runApp(
    LocalBudgetApp(
      repository: repository,
      capture: _androidCapture(dir),
      navigatorKey: appNavigatorKey,
    ),
  );
  BillNotifier.onOpen = (ruleId) => _openBillRule(repository, ruleId);
  final pending = BillNotifier.pendingOpenRuleId;
  if (pending != null) {
    BillNotifier.pendingOpenRuleId = null;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openBillRule(repository, pending),
    );
  }
}

/// Notification tap → the budgets sheet on the Bills tab with this rule's
/// occurrence open (§5). No context (teardown) → drop the hint; the list
/// stays the truth either way.
void _openBillRule(LedgerRepository repository, int ruleId) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  showBudgetsSheet(
    context,
    repository: repository,
    monthIndex: monthIndexOf(DateTime.now()),
    focusBillId: ruleId,
  );
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
    this.navigatorKey,
  });

  final LedgerRepository repository;
  final CaptureServices? capture;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode? themeMode;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      navigatorKey: navigatorKey,
      theme: theme ?? AppTheme.light(),
      darkTheme: darkTheme ?? AppTheme.dark(),
      themeMode: themeMode,
      home: LedgerScreen(repository: repository, capture: capture),
    );
  }
}
