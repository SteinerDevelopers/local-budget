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
import 'features/cloud/auto_backup.dart';
import 'features/cloud/cloud_hub.dart';
import 'features/ledger/ledger_screen.dart';
import 'features/manage/io.dart';
import 'features/reports/reports_screen.dart';
import 'features/support/support_services.dart';
import 'features/support/transfer.dart';
import 'features/widgets/widget_bridge.dart';
import 'features/widgets/widget_snapshot_service.dart';
import 'flavor.dart';

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

/// E7c §4.2: the widget snapshot pipeline, pro boots only — replaced (and
/// its subscription cancelled) on every boot, same lifecycle as [_tips].
WidgetSnapshotService? _widgetService;
_WidgetResumeObserver? _widgetObserver;

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
  // Bill reminders: boot OFF the first-frame path (inert where unavailable,
  // §5). Field test (Coosea SL219A): awaiting it here cost the full 5 s cap
  // on a budget phone — its notification dialog outran any boot-time cap —
  // and a cold-launch notification tap still hands off, because assigning
  // [BillNotifier.onOpen] below drains a pending tap in either order.
  unawaited(BillNotifier.bootstrap());
  // E7b §3.3: the daily auto-backup schedule is a paid-pack feature; the
  // free flavor never initialises WorkManager at all.
  if (FeatureFlags.proTrio) await initCloudAutoBackups(dir);
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
  // Kept in a library variable too: widget-route and notification sheet
  // entrances (_openWidgetRoute, _openBillRule) hand the same instance to
  // the budgets sheet so its Bills tab matches the home screen's.
  _capture = _androidCapture(dir);
  runApp(
    LocalBudgetApp(
      repository: repository,
      db: db,
      fx: fx,
      integrity: integrity,
      docsDir: dir,
      capture: _capture,
      navigatorKey: appNavigatorKey,
      restore: (backup) => restoreFromBackup(backup, docsDir: dir),
      tips: _tips,
      transfer: buildTransfer(),
      // E7b — the paid-pack cloud stack exists only in pro; free builds
      // never construct the keystore-backed hub (FeatureFlags.proTrio).
      cloud: FeatureFlags.proTrio ? _cloudHub(dir) : null,
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
  // Installing the handler drains a cold-launch tap in either order (the
  // setter checks [BillNotifier.pendingOpenRuleId]); the open rides the
  // next frame so the navigator's overlay exists, exactly as the old
  // manual drain did.
  BillNotifier.onOpen = (ruleId) => WidgetsBinding.instance
      .addPostFrameCallback((_) => _openBillRule(repository, ruleId));
  // E7c §4.2 — the widget pipeline is Paid-pack: only pro feeds the
  // home-screen trio or resolves its taps; the free flavor has no
  // receivers, so there is nothing to publish to or navigate from.
  _widgetService?.stop();
  _widgetService = null;
  final staleWidgetObserver = _widgetObserver;
  if (staleWidgetObserver != null) {
    WidgetsBinding.instance.removeObserver(staleWidgetObserver);
    _widgetObserver = null;
  }
  if (FeatureFlags.proTrio) {
    final widgets = _widgetService = WidgetSnapshotService(
      repository: repository,
      sink: WidgetBridge.publish,
    );
    widgets.start();
    WidgetBridge.onRoute((route) => _openWidgetRoute(repository, route));
    // A cold tap lands in the Kotlin mailbox before this frame exists.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _takeWidgetRoute(repository),
    );
    _widgetObserver = _WidgetResumeObserver(widgets);
    WidgetsBinding.instance.addObserver(_widgetObserver!);
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
  _widgetService?.stop();
  _widgetService = null;
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
  _widgetService?.stop();
  _widgetService = null;
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

/// Warm resume re-arms the widget month watch and refreshes the tiles: a
/// day spent in a pocket crossed midnight, and §4.3 keeps the widgets
/// honest about it without any Dart-side clock of its own.
class _WidgetResumeObserver with WidgetsBindingObserver {
  _WidgetResumeObserver(this._widgets);

  final WidgetSnapshotService _widgets;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _widgets.onResume();
  }
}

/// Cold start has no Dart listener while Kotlin parks the route, and warm
/// pushes race the frame they'd navigate on: both paths drain the single
/// mailbox, so every tap resolves exactly once, whenever a context exists.
Future<void> _takeWidgetRoute(LedgerRepository repository) async {
  final route = await WidgetBridge.takeRoute();
  if (route != null) _openWidgetRoute(repository, route);
}

/// The one Android capture instance (null elsewhere), shared by the widget
/// tree and the top-level widget-route/notification entrances.
CaptureServices? _capture;

/// §4.1 route hand-off: each widget lands on its promised screen, using
/// the same entry points the in-app buttons use — no second navigation
/// stack. No context (teardown edge) simply drops the tap, like bills.
void _openWidgetRoute(LedgerRepository repository, String route) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  switch (route) {
    case 'reports':
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportsScreen(repository: repository),
        ),
      );
    case 'budgets':
      showBudgetsSheet(
        context,
        repository: repository,
        monthIndex: monthIndexOf(DateTime.now()),
        capture: _capture,
      );
    case 'capture':
      // The capture flow lives in LedgerScreen's state (it owns the
      // CaptureServices wiring); the static hook is its front door.
      LedgerScreen.onOpenCapture?.call();
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
    capture: _capture,
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
  final renderer = ChannelPdfTextRenderer();
  return CaptureServices(
    intake: AndroidCaptureIntake(),
    extractor: MlKitTextExtractor(),
    renderer: renderer,
    // E11 §2 — the multi-page rasterizer as a concrete tear-off; the
    // TextRenderer interface alone can only ever offer page 1.
    scannedPdfPages: renderer.renderPages,
    store: AttachmentStore(docsDir),
    shares: PluginShareIngest(),
    // Tier 3 (issue #29): one fire-and-forget availability probe at startup;
    // absent AICore means false and the pipeline behaves exactly like E1.
    structurerFor: GeminiNanoStructurer().forCurrency,
  );
}

/// E7b §3.1 — destinations JSON in the app-private dir (label/URL/user
/// only; the password lives in flutter_secure_storage behind the hub).
CloudHub _cloudHub(Directory dir) => cloudHubFor(dir);

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
    this.cloud,
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

  /// E7b paid-pack cloud stack (null in free/tests/goldens ⇒ no tile).
  final CloudHub? cloud;

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
        cloud: cloud,
      ),
    );
  }
}
