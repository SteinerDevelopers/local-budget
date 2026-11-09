import 'dart:async';
import 'dart:io' show Directory;

import 'package:billing/billing.dart' show TipService;
import 'package:capture/capture.dart'
    show CapturePipeline, DocumentExtractor, DocumentRouter, DocRoute;
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/panel_add_bar.dart';
import '../../design/tokens.dart';
import '../../flavor.dart';
import '../budgets/home_panel.dart';
import '../capture/capture_intake.dart';
import '../capture/capture_services.dart';
import '../capture/capture_source_sheet.dart';
import '../capture/review_sheet.dart';
import 'package:local_budget/features/cloud/cloud_hub.dart';
import '../help/help_screen.dart';
import '../import/import_wizard_screen.dart';
import '../manage/icon_registry.dart';
import '../manage/io.dart';
import '../manage/manage_screen.dart';
import '../quickadd/quick_add_sheet.dart';
import '../reports/reports_screen.dart';
import '../support/transfer.dart';
import 'balance_strip.dart';
import 'day_label.dart';
import 'empty_month.dart';
import 'transaction_detail_sheet.dart';
import 'transaction_row.dart';
import 'view_models.dart';

/// Home of the app (§2.1): month switcher → balance strip → day groups → FAB.
/// Everything is derived from the drift stream; this screen only keeps paging
/// position and the QuickAdd warm state (§2.2 rule 5 lives with the caller).
class LedgerScreen extends StatefulWidget {
  /// E7c §4.1 — front door for the "Quick scan" widget: the capture flow
  /// (source sheet → picker → review) belongs to this state, which owns
  /// the CaptureServices wiring; a widget tap just rings this bell.
  static VoidCallback? onOpenCapture;

  const LedgerScreen({
    super.key,
    required this.repository,
    this.fx,
    this.integrity,
    this.db,
    this.docsDir,
    this.capture,
    this.io,
    this.restore,
    this.tips,
    this.transfer,
    this.cloud,
  });

  final LedgerRepository repository;

  /// E5 §6: device-base FX lookups at save time (null → no conversion; the
  /// row saves rate-less exactly like pre-E5 manual rows).
  final FxService? fx;

  /// §7 boot integrity report for Manage's passive banner.
  final ValueNotifier<IntegrityReport?>? integrity;

  /// The live database — Manage's Data section flows (export/backup/restore)
  /// work on it directly (§1–§3).
  final AppDatabase? db;

  /// Documents dir — restore's `applyRestore` root (§3).
  final Directory? docsDir;

  /// E2 capture services (intake + extractor + attachment store). Null on
  /// builds without platform capture (iOS until E5); the FAB then explains
  /// instead of dead-ending (§2.1 "never a dead end").
  final CaptureServices? capture;

  /// Data-section file boundary + cold-restart restore, handed to Manage
  /// (E5 §3); null ⇒ Manage uses RealIo / explains the Restore tile.
  final Io? io;
  final Future<void> Function(Backup backup)? restore;

  /// E6 §5 tips layer + §3 transfer channel, handed to Manage (null ⇒ the
  /// coffee sheet / copy row explain themselves, off-device).
  final TipService? tips;
  final FreeTransfer? transfer;

  /// E7b paid-pack cloud stack, handed down to Manage; free builds never
  /// forward it (FeatureFlags.proTrio gate in [_LedgerScreenState]
  /// `_openManage`, doubled by main.dart's construction gate).
  final CloudHub? cloud;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

// ---- month paging ----------------------------------------------------------

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June', //
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Paging index: months elapsed since 2000-01. Home has no date picker
/// (§2.1), the horizon is simply the PageView's itemCount.
const _monthCount = 12 * 100; // 2000-01 … 2099-12

int monthIndexOf(DateTime day) => (day.year - 2000) * 12 + day.month - 1;

DateTime _monthStart(int index) => DateTime(2000 + index ~/ 12, index % 12 + 1);

/// `November 2026` (§2.1 month-title).
String monthTitle(int index) {
  final m = _monthStart(index);
  return '${_monthNames[m.month - 1]} ${m.year}';
}

// ---- presentation mapping --------------------------------------------------

/// Default category icon (§2.1 row + §2.2 chips). #18 stores an icon key per
/// category ([ManageIcons.of]); this is the by-name fallback kept as the
/// public helper the #17 tests pin.
IconData categoryIcon(String? name) => ManageIcons.of(null, name);

/// Drift row → [EntryTile]; amount stays unsigned, sign is display-only (§3).
EntryTile tileFor(LedgerEntryData row, {required String baseCode}) => EntryTile(
  id: row.id,
  // Stored icon key wins (§2.4); name mapping is the pre-#18 fallback.
  icon: ManageIcons.of(row.categoryIcon, row.categoryName),
  title: row.categoryName ?? 'Uncategorized',
  // The payee leads when the row carries one (#45: what the scan review
  // stores must be what the list shows); manual rows keep their note.
  // Import rows store both, identically — the display is unchanged there.
  memo: (row.merchant?.isNotEmpty ?? false)
      ? row.merchant
      : ((row.note == null || row.note!.isEmpty) ? null : row.note),
  amount: Money(row.amountMinor, Currency.resolve(row.currencyCode)),
  kind: row.isIncome ? EntryKind.income : EntryKind.expense,
  day: row.day, // spoken in the row's TalkBack label (§5)
  missingRate: row.currencyCode != baseCode && row.baseAmountMinor == null,
);

/// Sums one month **in the device base currency** (hardening #22): base-
/// currency rows count at face value, foreign rows at their FX snapshot
/// (`baseAmountMinor`) — raw minor units must never be added across
/// currencies (¥1,485 is not $14.85). A foreign row without a snapshot is
/// skipped, never guessed. Income/expenses stay unsigned, the labels carry
/// the sign (§2.1).
BalanceSummary summarizeMonth(List<LedgerEntryData> rows, Currency currency) {
  var income = 0;
  var expenses = 0;
  for (final r in rows) {
    final minor = r.currencyCode == currency.code
        ? r.amountMinor
        : r.baseAmountMinor;
    if (minor == null) continue;
    if (r.isIncome) {
      income += minor;
    } else {
      expenses += minor;
    }
  }
  return BalanceSummary(
    income: Money(income, currency),
    expenses: Money(expenses, currency),
  );
}

/// Interleaves day headers with their rows for a flat list (§2.1 sort:
/// newest day first; newest row first within a day — `watchMonth` already
/// orders by dateDays DESC, id DESC).
List<Object> _flattenDays(List<LedgerEntryData> rows) {
  final out = <Object>[];
  DateTime? day;
  for (final r in rows) {
    if (day == null || r.day != day) {
      out.add(r.day);
      day = r.day;
    }
    out.add(r);
  }
  return out;
}

// ---- screen state ----------------------------------------------------------

class _LedgerScreenState extends State<LedgerScreen> {
  late final PageController _pages = PageController(initialPage: _index0);
  late int _index = _index0;

  /// Bottom-nav destination (owner IA pass, 2026-11-05): 0 Receipts —
  /// the month ledger; 1..3 Budgets/Bills/Goals — the embedded HomePanel.
  int _dest = 0;

  /// Warm state the sheet gets next time it opens (§2.2 rule 5: "carried by
  /// the caller"): kind + chip of the last saved entry.
  EntryKind _warmKind = EntryKind.expense;
  int? _warmCategoryId;

  /// Device base currency (decision 6); 'USD' until the setting resolves.
  Currency _currency = Currency.resolve('USD');

  /// Home month resolved per State instance, not per class load (hardening
  /// #20): an app left open overnight gets a fresh "today" on relaunch of
  /// the screen instead of a month frozen since process start.
  late final int _index0 = monthIndexOf(DateTime.now());

  // ---- external share / open-with (§5, decision 5) -------------------------

  StreamSubscription<List<CapturePick>>? _shareSub;

  /// A share delivered before the first frame must wait for layout — the
  /// bottom sheet needs a built context to open into.
  bool _shareReady = false;
  final List<List<CapturePick>> _pendingShares = [];

  @override
  void initState() {
    super.initState();
    LedgerScreen.onOpenCapture = _openCapture;
    _loadCurrency();
    _listenShares();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shareReady = true;
      for (final batch in List<List<CapturePick>>.of(_pendingShares)) {
        _pendingShares.remove(batch);
        _onShares(batch);
      }
    });
  }

  /// Share / open-with ingest: cold-start share + the running stream, both
  /// routed through [_onShares]. Null `shares` (iOS until E5, tests without
  /// the plugin) means nothing is ever listened to.
  void _listenShares() {
    final ingest = widget.capture?.shares;
    if (ingest == null) return;
    _shareSub = ingest.stream.listen(_onShares);
    ingest.initial().then(_onShares);
  }

  /// Decision 5 verbatim: multiple shared files import **the first**, the
  /// rest get one honest snackbar — never a queue, never auto-commit.
  void _onShares(List<CapturePick> picks) {
    if (picks.isEmpty) return;
    if (!_shareReady) {
      _pendingShares.add(picks);
      return;
    }
    if (picks.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Files import one at a time — the first one opened.'),
        ),
      );
    }
    _reviewPick(picks.first, fromShare: true);
  }

  @override
  void dispose() {
    if (LedgerScreen.onOpenCapture == _openCapture) {
      LedgerScreen.onOpenCapture = null;
    }
    _shareSub?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Base currency feeds the strip + QuickAdd's keypad; re-read after Manage
  /// changes it (#18).
  Future<void> _loadCurrency() async {
    final code = await widget.repository.baseCurrency();
    if (mounted) setState(() => _currency = Currency.resolve(code ?? 'USD'));
  }

  void _animate(int target) {
    if (!_pages.hasClients || target < 0 || target >= _monthCount) return;
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openQuickAdd() async {
    final cats = await widget.repository.categories();
    if (!mounted) return;
    final entry = await showQuickAdd(
      context,
      categories: [
        for (final c in cats)
          CategoryOption(c.id, c.name, ManageIcons.of(c.icon, c.name)),
      ],
      currency: _currency,
      initialKind: _warmKind,
      initialCategoryId: _warmCategoryId,
      // §2.4: the sheet's Manage chip pops it and lands here.
      onManageCategories: _openManage,
    );
    if (entry == null || !mounted) return;
    // E5 §6: a foreign-currency save snapshots the device-base rate at
    // insert time. The lookup is bounded (2 s) and never throws — a null
    // rate still saves the row; the ledger then flags it "No rate".
    String? baseCode;
    double? rate;
    final fx = widget.fx;
    if (fx != null && entry.amount.currency.code != _currency.code) {
      baseCode = _currency.code;
      rate = await fx.rateForDeviceBase(entry.amount.currency.code);
      if (!mounted) return;
    }
    await widget.repository.addEntry(
      date: entry.day,
      amount: entry.amount,
      isIncome: entry.kind == EntryKind.income,
      categoryId: entry.categoryId,
      note: entry.note,
      baseCurrencyCode: baseCode,
      fxRate: rate,
    );
    if (!mounted) return;
    setState(() {
      _warmKind = entry.kind;
      _warmCategoryId = entry.categoryId;
    });
    // Saved via the inline calendar into another month? Follow it.
    _animate(monthIndexOf(entry.day));
  }

  /// E2 §1/§2.1: source sheet → platform picker → Review → one write. A
  /// null return at any step (back-out, cancelled picker) leaves the ledger
  /// untouched — decision 5's "never auto-commit" in code form.
  Future<void> _openCapture() async {
    final services = widget.capture;
    if (services == null) {
      // Real intake lands with the Android adapters (#28); iOS is E5.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt capture is not available in this build.'),
        ),
      );
      return;
    }
    final choice = await showCaptureSourceSheet(
      context,
      showScreenshotRow: services.intake.hasScreenshotRow,
    );
    if (choice == null || !mounted) return;
    CapturePick? pick;
    try {
      pick = await services.intake.pick(choice);
    } catch (_) {
      // A picker that fails is "user changed their mind" plus one honest
      // line — the ledger is still untouched (§2.1).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read that file — nothing was saved.'),
          ),
        );
      }
      return;
    }
    if (pick == null || !mounted) return;
    await _reviewPick(pick);
  }

  /// The Review half of every capture entry point — source-sheet picks and
  /// external shares converge here (decision 5: one document → one review →
  /// at most one write, whoever initiated it).
  Future<void> _reviewPick(CapturePick pick, {bool fromShare = false}) async {
    final services = widget.capture;
    if (services == null || !mounted) return;
    // E11 §5 — a shared *statement* is the one thing Review is wrong for.
    // A cheap sniff (text layer, or page 1 only — never a 10-page OCR)
    // offers the wizard hand-off; declining or any ambiguity keeps today's
    // receipt-first Review exactly as it was.
    if (fromShare &&
        pick.choice == CaptureChoice.pdf &&
        widget.db != null &&
        widget.io != null) {
      final looksLikeStatement = await _sniffStatement(services, pick);
      if (!mounted) return;
      if (looksLikeStatement) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Looks like a statement'),
            content: const Text(
              'Import it to review the rows before anything is saved.',
            ),
            actions: [
              TextButton(
                key: const Key('share-read-receipt'),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Read as receipt'),
              ),
              FilledButton(
                key: const Key('share-open-import'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open Import'),
              ),
            ],
          ),
        );
        if (go == true && mounted) {
          final db = widget.db!, io = widget.io!;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ImportWizardScreen(
                repository: widget.repository,
                db: db,
                io: io,
                capture: services,
              ),
            ),
          );
          return;
        }
        if (!mounted) return;
      }
    }
    final cats = await widget.repository.categories();
    if (!mounted) return;
    final captured = await showCaptureReview(
      context,
      source: pick.choice.source,
      imageBytes: pick.bytes,
      pipeline: CapturePipeline(
        currency: _currency,
        extractor: services.extractor,
        // Currency-bound Tier-3 view (issue #29); null = OCR only.
        structurer: services.structurerFor?.call(_currency),
      ),
      categories: [
        for (final c in cats)
          CategoryOption(c.id, c.name, ManageIcons.of(c.icon, c.name)),
      ],
      warmCategoryId: _warmCategoryId,
      onManageCategories: _openManage,
      renderer: services.renderer,
      merchantLookup: widget.repository.merchantsLike,
    );
    if (captured == null || !mounted) return;
    await _saveCaptured(captured, fileExtension: pick.choice.fileExtension);
  }

  /// Cheap statement sniff for the share hand-off (E11 §5): trust the text
  /// layer when there is one, else OCR page 1 only — deliberately without
  /// the wizard's `scannedPdfPages` cap. A shared receipt must never pay
  /// ten OCR passes for a dialog it will not show; a false negative just
  /// means the owner gets Review, which is what shares always did.
  Future<bool> _sniffStatement(
    CaptureServices services,
    CapturePick pick,
  ) async {
    try {
      final read = await DocumentExtractor(
        extractor: services.extractor,
        renderer: services.renderer,
      ).fromPdf(pick.bytes);
      if (read == null || read.isEmpty) return false;
      return DocumentRouter.route(read.lines, currency: _currency) ==
          DocRoute.statement;
    } on Object {
      return false;
    }
  }

  /// The one write (decision 5): original saved first so the row can carry
  /// its path, then the transaction with `source` + `imageRef` + merchant —
  /// upsert of the merchant row is the repository's job (§4, case-insensitive).
  /// A failed insert unlinks the orphaned original; nothing else is rolled
  /// back because nothing else happened.
  Future<void> _saveCaptured(
    CapturedEntry captured, {
    required String fileExtension,
  }) async {
    final store = widget.capture?.store;
    final bytes = captured.imageBytes;
    String? imageRef;
    if (store != null && bytes != null) {
      imageRef = store.saveOriginal(
        bytes,
        extension: fileExtension,
        source: captured.source,
      );
    }
    try {
      final account = await widget.repository.defaultAccount();
      await widget.repository.addTransaction(
        accountId: account.id,
        date: captured.entry.day,
        amount: captured.entry.amount,
        source: captured.source,
        categoryId: captured.entry.categoryId,
        merchant: captured.merchant,
        isIncome: captured.entry.kind == EntryKind.income,
        imageRef: imageRef,
      );
    } catch (_) {
      if (imageRef != null && store != null) {
        try {
          store.delete(imageRef);
        } catch (_) {
          // An orphaned original is harmless; Review already closed.
        }
      }
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      _warmKind = captured.entry.kind;
      _warmCategoryId = captured.entry.categoryId;
    });
    _animate(monthIndexOf(captured.entry.day));
  }

  Future<void> _openManage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManageScreen(
          repository: widget.repository,
          fx: widget.fx,
          integrity: widget.integrity,
          db: widget.db,
          docsDir: widget.docsDir,
          io: widget.io ?? const RealIo(),
          capture: widget.capture,
          restore: widget.restore,
          tips: widget.tips,
          transfer: widget.transfer,
          cloud: FeatureFlags.proTrio ? widget.cloud : null,
        ),
      ),
    );
    // Base currency may have changed (§2.4); categories re-read themselves
    // the next time the FAB opens.
    _loadCurrency();
  }

  /// Swipe-to-dismiss → SnackBar "Deleted / Undo" (§2.1). Undo is the only
  /// delete safety net — zero dialogs — and reuses the exact row id.
  Future<void> _delete(int id) async {
    final removed = await widget.repository.deleteEntry(id);
    if (removed == null || !mounted) return;
    final image = removed.imageRef;
    final store = widget.capture?.store;
    if (image != null && store != null) {
      // E2 §4: the original unlinks only after the row is committed gone,
      // and Undo restores the row without the image (no re-save).
      try {
        store.delete(image);
      } catch (_) {
        // Orphaned file — harmless until M2 sweeps.
      }
    }
    final restored = image == null
        ? removed
        : removed.copyWith(imageRef: const Value(null));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('Deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.restoreEntry(restored),
        ),
      ),
    );
  }

  /// E5 §6: row tap opens the read-only detail sheet. Delete comes back as
  /// a sheet *result* so the Undo SnackBar stays the single safety net —
  /// the sheet itself never deletes.
  Future<void> _openDetail(LedgerEntryData row) async {
    final action = await showTransactionDetail(
      context,
      repository: widget.repository,
      entry: row,
      baseCode: _currency.code,
      attachments: widget.capture?.store,
    );
    if (action == 'delete' && mounted) await _delete(row.id);
  }

  /// E4 §1: Reports sits behind one icon in the month header — the month
  /// ledger stays the app's home; no nav entry, no chrome.
  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(repository: widget.repository),
      ),
    );
  }

  /// E8 §3: Help sits a tap away from the app’s home screen, not buried
  /// in Manage (feasibility: reachable from every screen).
  void _openHelp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Owner IA pass, 2026-11-05: Receipts / Bills / Budgets / Goals switch
    // from a bottom bar on the home screen — no more sheet buried behind a
    // stat tap. Receipts is the month ledger itself; the other three are
    // the budgets-sheet bodies, embedded (the sheet survives for
    // notification deep-links, which own their focus target).
    return Scaffold(
      body: SafeArea(
        child: _dest == 0
            ? Column(
                children: [
                  _MonthHeader(
                    title: monthTitle(_index),
                    onPrevious: () => _animate(_index - 1),
                    onNext: () => _animate(_index + 1),
                    onOpenReports: _openReports,
                    onOpenHelp: _openHelp,
                    onOpenManage: _openManage,
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _monthCount,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _MonthPage(
                        repository: widget.repository,
                        index: i,
                        currency: _currency,
                        onDelete: _delete,
                        onOpen: _openDetail,
                        onOpenBudgets: () => setState(() => _dest = 2),
                      ),
                    ),
                  ),
                  // Owner standardization, 2026-11-05: Receipts adds through
                  // the same bar the Bills panel uses — the E2 FABs are
                  // retired. The scanner button follows the Bills rule:
                  // present where capture exists, hidden where it doesn't.
                  PanelAddBar(
                    primary: TextButton.icon(
                      key: const ValueKey('receipt-add'),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add receipt'),
                      onPressed: _openQuickAdd,
                    ),
                    secondary: widget.capture == null
                        ? null
                        : TextButton.icon(
                            key: const ValueKey('receipt-add-document'),
                            icon: const Icon(
                              Icons.document_scanner_outlined,
                              size: 20,
                            ),
                            label: const Text('Scan a receipt'),
                            onPressed: _openCapture,
                          ),
                  ),
                ],
              )
            : HomePanel(
                // One element across Budgets/Bills/Goals: month and load
                // state survive switching; the ledger's month follows.
                key: const ValueKey('home-panel'),
                repository: widget.repository,
                tab: _dest - 1,
                initialMonthIndex: _index,
                currency: _currency,
                capture: widget.capture,
                onOpenManage: _openManage,
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _dest,
        onDestinationSelected: (i) => setState(() => _dest = i),
        destinations: const [
          NavigationDestination(
            key: ValueKey('nav-receipts'),
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Receipts',
          ),
          NavigationDestination(
            key: ValueKey('nav-bills'),
            icon: Icon(Icons.event_outlined),
            label: 'Bills',
          ),
          NavigationDestination(
            key: ValueKey('nav-budgets'),
            icon: Icon(Icons.pie_chart_outline),
            label: 'Budgets',
          ),
          NavigationDestination(
            key: ValueKey('nav-goals'),
            icon: Icon(Icons.flag_outlined),
            label: 'Goals',
          ),
        ],
      ),
    );
  }
}

// ---- widgets ---------------------------------------------------------------

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.title,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenReports,
    required this.onOpenHelp,
    required this.onOpenManage,
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenHelp;
  final VoidCallback onOpenManage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // IconButton defaults to the 48 dp hit target (§2.1).
            IconButton(
              tooltip: 'Previous month',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left, size: 28),
            ),
            Expanded(
              child: GestureDetector(
                // Dragging the header pages months too (§2.1); the body
                // pages through the PageView itself.
                onHorizontalDragEnd: (drag) {
                  final v = drag.primaryVelocity ?? 0;
                  if (v < -50) {
                    onNext();
                  } else if (v > 50) {
                    onPrevious();
                  }
                },
                child: Center(
                  // E3 (#52): the title's corridor is the icons' leftover —
                  // no reflow room exists at 200%, so the text shrinks to
                  // fit instead of losing its year. FittedBox sheds only
                  // what the corridor lacks; at the default scale it is a
                  // no-op and the §2.1 pixel budget is untouched.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: Tokens.monthLabelSize, // §2.1 month-title
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right, size: 28),
            ),
            // E4 §1: the only entrance to Reports (e4-reports.md §1).
            IconButton(
              key: const Key('reports-open'),
              tooltip: 'Reports',
              onPressed: onOpenReports,
              icon: const Icon(Icons.insights_outlined, size: 24),
            ),
            // E8 §3: "?" joins the same cluster — Help is a first-class
            // destination, reachable from the home screen directly.
            IconButton(
              key: const Key('help-open'),
              tooltip: 'Help',
              onPressed: onOpenHelp,
              icon: const Icon(Icons.help_outline, size: 24),
            ),
            // Owner 2026-11-04 pm: Manage joins the cluster too —
            // reaching it used to mean opening a sheet and hunting the
            // chip at the end of a scrolled row.
            IconButton(
              key: const Key('manage-open'),
              tooltip: 'Manage',
              onPressed: onOpenManage,
              icon: const Icon(Icons.settings_outlined, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPage extends StatefulWidget {
  const _MonthPage({
    required this.repository,
    required this.index,
    required this.currency,
    required this.onDelete,
    required this.onOpen,
    required this.onOpenBudgets,
  });

  final LedgerRepository repository;
  final int index;
  final Currency currency;
  final Future<void> Function(int id) onDelete;

  /// E5 §6: row tap → read-only detail sheet (manual rate lives there).
  final void Function(LedgerEntryData row) onOpen;

  /// Owner IA pass (2026-11-05): the Expenses stat used to open the
  /// budgets sheet; the bottom nav made Budgets a first-class destination,
  /// so the stat just switches panels.
  final VoidCallback onOpenBudgets;

  @override
  State<_MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<_MonthPage> {
  /// One subscription per page — `watchMonth` mints a fresh stream per
  /// call, so it must not be rebuilt on every frame.
  late final Stream<List<LedgerEntryData>> _rows = widget.repository.watchMonth(
    yearMonthOf(_monthStart(widget.index)),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerEntryData>>(
      stream: _rows,
      initialData: const [],
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <LedgerEntryData>[];
        return Column(
          children: [
            BalanceStrip(
              summary: summarizeMonth(rows, widget.currency),
              onExpensesTap: widget.onOpenBudgets,
            ),
            Expanded(
              // Empty month keeps header + strip (zeros) on screen (§2.1).
              child: rows.isEmpty
                  ? const EmptyMonth()
                  : _DayList(
                      rows: rows,
                      baseCode: widget.currency.code,
                      onDelete: widget.onDelete,
                      onOpen: widget.onOpen,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.rows,
    required this.baseCode,
    required this.onDelete,
    required this.onOpen,
  });

  final List<LedgerEntryData> rows;
  final String baseCode;
  final Future<void> Function(int id) onDelete;
  final void Function(LedgerEntryData row) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = _flattenDays(rows);
    // Owner standardization, 2026-11-05 (tester note): Receipts wears the
    // Bills list's hairline between rows so the two panels read as one
    // family. The line sits between two transactions only — a day header
    // is its own separator. The retired FAB's clearance is gone; the
    // PanelAddBar below is the list's floor, exactly like Bills.
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      itemCount: items.length,
      separatorBuilder: (_, i) =>
          items[i] is DateTime || items[i + 1] is DateTime
          ? const SizedBox.shrink()
          : const Divider(height: 1, thickness: 0.5),
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateTime) return _DayHeader(day: item);
        final row = item as LedgerEntryData;
        return Dismissible(
          key: ValueKey('entry-${row.id}'),
          direction: DismissDirection.endToStart,
          background: const _DeleteBackground(),
          // Await the delete so the row is gone from the stream when the
          // dismiss animation finishes — no "still in tree" tear.
          confirmDismiss: (_) async {
            await onDelete(row.id);
            return true;
          },
          child: TransactionRow(
            tile: tileFor(row, baseCode: baseCode),
            onTap: () => onOpen(row),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    // §5: day groups are announced as section headers.
    return Semantics(
      header: true,
      child: SizedBox(
        // §2.1: 32 dp header row including spacing.
        height: 32,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            child: Text(DayLabel.of(day), style: Tokens.labelCaps(context)),
          ),
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: Tokens.rowHeight,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
      color: scheme.errorContainer,
      // Decorative — the Dismissible's own semantics carry the action (§5);
      // Icon never leaks its glyph as a label.
      child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
    );
  }
}
