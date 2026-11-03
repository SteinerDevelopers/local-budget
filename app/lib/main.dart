import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:billing/billing.dart' show TipService;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'design/theme.dart';
import 'features/bills/bill_notifier.dart';
import 'features/bills/bills_service.dart'
    show MaterializeOutcome, materializeDueBills;
import 'features/budgets/budgets_sheet.dart';
import 'features/capture/android_capture_intake.dart';
import 'features/capture/adapters/channel_pdf_text_renderer.dart';
import 'features/capture/adapters/gemini_nano_structurer.dart';
import 'features/capture/adapters/ml_kit_text_extractor.dart';

import 'features/capture/capture_services.dart';
import 'features/ledger/ledger_screen.dart';
import 'features/manage/io.dart';
import 'features/support/support_services.dart';
import 'features/support/transfer.dart';

/// The navigator notification taps resolve against (§5: tap opens the bill).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// The live database handle. Restore (§3) must close it before swapping the
/// file, and the cold restart reopens a fresh one — hence held here, not
/// buried inside the repository.
AppDatabase? _liveDb;
_BillMaterializeObserver? _observer;

/// E6: one tips service per boot (its purchase-stream subscription belongs
/// to this boot's repository); rebuilt by [restartLocalBudget]'s boot.
TipService? _tips;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootLocalBudget();
}

/// Full cold boot: open the database, seed defaults, run the pre-frame bill
/// pass, mount the app. Called once by [main] and again by
/// [restartLocalBudget] after a restore (the only destructive path, §3).
Future<void> bootLocalBudget() async {
  // One SQLite file in the app's private directory — nothing leaves the
  // device (decision 8: zero collection).
  final dir = await getApplicationDocumentsDirectory();
  final db = _liveDb = AppDatabase.openFile('${dir.path}/localbudget.sqlite');
  final repository = LedgerRepository(db);
  // E5 §6: the one network touch, injected from here; tests hand their own.
  final fx = FxService(db);
  // §7: the boot-time integrity report, surfaced *passively* in Manage.
  final integrity = ValueNotifier<IntegrityReport?>(null);
  // First launch seeds the Cash account + default categories; idempotent.
  await repository.ensureDefaults();
  // Bill reminders: time zone + channel init (inert where unavailable, §5).
  await BillNotifier.bootstrap();
  // §3.4 lazy materialization before the first frame, so the ledger the
  // user lands on already contains this pass's occurrences. The pass is
  // day-gated + race-gated: warm resumes below are cheap replays. Bounded
  // because a wedged pass must not eat the first frame — the bill still
  // surfaces as a Due row and the next open replays the pass (§5 ethos).
  MaterializeOutcome? pass;
  try {
    pass = await materializeDueBills(
      repository,
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('bill materialization skipped: $e');
  }
  await _tips?.dispose();
  _tips = buildTipService(repository);
  runApp(
    LocalBudgetApp(
      repository: repository,
      db: db,
      fx: fx,
      integrity: integrity,
      docsDir: dir,
      capture: _androidCapture(dir),
      navigatorKey: appNavigatorKey,
      restore: (backup) => restoreFromBackup(backup, docsDir: dir),
      tips: _tips,
      transfer: buildTransfer(),
    ),
  );
  // §7: the integrity pass runs *after* the app is up — never on the boot
  // critical path, never a dialog, never a crash; a report only lights the
  // banner in Manage and the debug log.
  unawaited(_checkIntegrity(db, integrity));
  if (pass case final outcome?) _surfaceStaleBills(outcome.pausedRuleIds);
  // Replace (never stack) the observer across cold restarts.
  final observer = _observer;
  if (observer != null) WidgetsBinding.instance.removeObserver(observer);
  _observer = _BillMaterializeObserver(repository);
  WidgetsBinding.instance.addObserver(_observer!);
  BillNotifier.onOpen = (ruleId) => _openBillRule(repository, ruleId);
  final pending = BillNotifier.pendingOpenRuleId;
  if (pending != null) {
    BillNotifier.pendingOpenRuleId = null;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openBillRule(repository, pending),
    );
  }
}

/// §7 passive check: `DbIntegrity.check` already never throws; the catch is
/// for a database that cannot even be opened, and even then the app boots.
Future<void> _checkIntegrity(
  AppDatabase db,
  ValueNotifier<IntegrityReport?> target,
) async {
  try {
    final report = await DbIntegrity.check(db);
    if (!report.ok) {
      debugPrint('integrity: ${report.problems.join('; ')}');
      target.value = report;
    }
  } catch (e) {
    debugPrint('integrity check skipped: $e');
  }
}

/// Cold restart after `applyRestore` (§3): tear the widget tree down first
/// (cancelling every drift stream), then close, then boot a fresh stack.
/// The blank-root `runApp` is the documented cold-restart trick — same-type
/// roots would otherwise keep stale state by slot.
Future<void> restartLocalBudget() async {
  runApp(const SizedBox.shrink());
  await Future<void>(() {}); // let the old tree unmount (streams cancel)
  final db = _liveDb;
  _liveDb = null;
  await db?.close();
  await bootLocalBudget();
}

/// Cold restore from an opened backup (E5 §3): the tree goes blank first so
/// every drift stream is cancelled, the SQLite file is swapped while the
/// handle is closed, then the ordinary boot runs — there is no second
/// startup path to keep in sync. Nothing after this returns: the process
/// has effectively restarted.
Future<void> restoreFromBackup(
  Backup backup, {
  required Directory docsDir,
}) async {
  runApp(const SizedBox.shrink());
  await Future<void>(() {}); // let the old tree unmount (streams cancel)
  final db = _liveDb;
  _liveDb = null;
  await db?.close();
  await applyRestore(
    backup,
    dbPath: '${docsDir.path}/localbudget.sqlite',
    root: docsDir,
  );
  await bootLocalBudget();
}

/// Warm resume runs the same pass (§3.4: "cold or warm resume"). Same-day
/// and in-flight gates inside the service keep rapid resumes idempotent.
class _BillMaterializeObserver with WidgetsBindingObserver {
  _BillMaterializeObserver(this.repository);

  final LedgerRepository repository;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      materializeDueBills(
        repository,
      ).then((outcome) => _surfaceStaleBills(outcome.pausedRuleIds)),
    );
  }
}

bool _pausedSurfaced = false;

/// §3.4 "paused?": one gentle nudge per session; the Bills rows keep
/// asking afterwards, so missing the snack bar loses nothing.
void _surfaceStaleBills(List<int> pausedRuleIds) {
  if (pausedRuleIds.isEmpty || _pausedSurfaced) return;
  _pausedSurfaced = true;
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(
          'A bill hasn’t come due in over a year — open Bills to resume '
          'or pause it.',
        ),
      ),
    );
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
    this.db,
    this.fx,
    this.integrity,
    this.docsDir,
    this.capture,
    this.theme,
    this.darkTheme,
    this.themeMode,
    this.navigatorKey,
    this.io,
    this.restore,
    this.tips,
    this.transfer,
  });

  final LedgerRepository repository;

  /// The live handle behind [repository] — the Data section's export and
  /// backup snapshots run on it; restore closes it (§3).
  final AppDatabase? db;

  /// E5 §6: FX lookups (null in tests that never exercise currency — the
  /// entry sheet then behaves exactly like E1).
  final FxService? fx;

  /// §7 boot integrity report, set off the critical path; Manage's banner
  /// listens. Null in tests/goldens (no banner).
  final ValueNotifier<IntegrityReport?>? integrity;

  /// App documents dir — the SQLite file's home and `applyRestore`'s root.
  final Directory? docsDir;
  final CaptureServices? capture;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode? themeMode;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// File boundary for the Data section; null ⇒ ManageScreen's RealIo.
  final Io? io;

  /// Cold-restart restore (E5 §3); null ⇒ the Restore tile explains itself.
  final Future<void> Function(Backup backup)? restore;

  /// E6 §5 coffee tips + §3 transfer channel, handed down to Manage via
  /// LedgerScreen; null (tests, goldens, non-Android) ⇒ both explain.
  final TipService? tips;
  final FreeTransfer? transfer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      navigatorKey: navigatorKey,
      theme: theme ?? AppTheme.light(),
      darkTheme: darkTheme ?? AppTheme.dark(),
      themeMode: themeMode,
      home: LedgerScreen(
        repository: repository,
        fx: fx,
        integrity: integrity,
        db: db,
        docsDir: docsDir,
        capture: capture,
        io: io,
        restore: restore,
        tips: tips,
        transfer: transfer,
      ),
    );
  }
}
