import 'dart:async';

import 'package:capture/capture.dart' show CapturePipeline;
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../budgets/budgets_sheet.dart';
import '../capture/capture_intake.dart';
import '../capture/capture_services.dart';
import '../capture/capture_source_sheet.dart';
import '../capture/review_sheet.dart';
import '../manage/icon_registry.dart';
import '../manage/manage_screen.dart';
import '../quickadd/quick_add_sheet.dart';
import '../reports/reports_screen.dart';
import 'balance_strip.dart';
import 'day_label.dart';
import 'empty_month.dart';
import 'transaction_row.dart';
import 'view_models.dart';

/// Home of the app (§2.1): month switcher → balance strip → day groups → FAB.
/// Everything is derived from the drift stream; this screen only keeps paging
/// position and the QuickAdd warm state (§2.2 rule 5 lives with the caller).
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.repository, this.capture});

  final LedgerRepository repository;

  /// E2 capture services (intake + extractor + attachment store). Null on
  /// builds without platform capture (iOS until E5); the FAB then explains
  /// instead of dead-ending (§2.1 "never a dead end").
  final CaptureServices? capture;

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
EntryTile tileFor(LedgerEntryData row) => EntryTile(
  id: row.id,
  // Stored icon key wins (§2.4); name mapping is the pre-#18 fallback.
  icon: ManageIcons.of(row.categoryIcon, row.categoryName),
  title: row.categoryName ?? 'Uncategorized',
  memo: (row.note == null || row.note!.isEmpty) ? null : row.note,
  amount: Money(row.amountMinor, Currency.resolve(row.currencyCode)),
  kind: row.isIncome ? EntryKind.income : EntryKind.expense,
  day: row.day, // spoken in the row's TalkBack label (§5)
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
    _reviewPick(picks.first);
  }

  @override
  void dispose() {
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
    await widget.repository.addEntry(
      date: entry.day,
      amount: entry.amount,
      isIncome: entry.kind == EntryKind.income,
      categoryId: entry.categoryId,
      note: entry.note,
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
  Future<void> _reviewPick(CapturePick pick) async {
    final services = widget.capture;
    if (services == null || !mounted) return;
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
        builder: (_) => ManageScreen(repository: widget.repository),
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

  /// E4 §1: Reports sits behind one icon in the month header — the month
  /// ledger stays the app's home; no nav entry, no chrome.
  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _MonthHeader(
              title: monthTitle(_index),
              onPrevious: () => _animate(_index - 1),
              onNext: () => _animate(_index + 1),
              onOpenReports: _openReports,
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
                ),
              ),
            ),
          ],
        ),
      ),
      // E2 §1: two FABs live here and nowhere else — capture is secondary,
      // 12 dp above the primary add. Keys keep test finders unambiguous
      // now that the slot holds two FloatingActionButton-derived widgets.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            key: const ValueKey('fab-capture'),
            // The two FABs share one route, so only one may hold the
            // default hero tag — the primary keeps E1's exact behavior.
            heroTag: null,
            onPressed: _openCapture,
            tooltip: 'Add from receipt',
            child: const Icon(Icons.document_scanner_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            key: const ValueKey('fab-quickadd'),
            onPressed: _openQuickAdd,
            tooltip: 'Add transaction',
            child: const Icon(Icons.add),
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
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenReports;

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
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: Tokens.monthLabelSize, // §2.1 month-title
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
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
  });

  final LedgerRepository repository;
  final int index;
  final Currency currency;
  final Future<void> Function(int id) onDelete;

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
              onExpensesTap: () => showBudgetsSheet(
                context,
                repository: widget.repository,
                monthIndex: widget.index,
                currency: widget.currency,
              ),
            ),
            Expanded(
              // Empty month keeps header + strip (zeros) on screen (§2.1).
              child: rows.isEmpty
                  ? const EmptyMonth()
                  : _DayList(rows: rows, onDelete: widget.onDelete),
            ),
          ],
        );
      },
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.rows, required this.onDelete});

  final List<LedgerEntryData> rows;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    final items = _flattenDays(rows);
    return ListView.builder(
      // FAB clearance so the last row never hides under it.
      padding: const EdgeInsets.only(bottom: Tokens.space5 + 40),
      itemCount: items.length,
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
          child: TransactionRow(tile: tileFor(row)),
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
