import 'dart:async';
import 'dart:convert';

import 'package:budget/budget.dart';
import 'package:core/core.dart';
// LedgerE1 must be in the show-list: watchMonth/monthRange are declared in
// the data package's extensions and barrels, and `show` filters extensions.
import 'package:data/data.dart'
    show LedgerE1, LedgerRepository, monthRange, yearMonthOf;

import '../budgets/budgets_service.dart';

/// E7c §4.2 — Dart half of the widget pipeline: build the aggregates-only
/// snapshot and hand it to [WidgetSnapshotService.sink]; the native bridge
/// owns the file (`filesDir/widget/state.json`) and the widget refresh, so
/// this file has no I/O and no Flutter imports — pure, testable, and the
/// exact same code the pro entry point wires up.
typedef WidgetSnapshotSink = Future<void> Function(String json);

class WidgetSnapshotService {
  WidgetSnapshotService({
    required this.repository,
    required this.sink,
    DateTime Function()? clock,

    /// §4.2 "debounced 2 s after ledger writes": one coalesced write per
    /// burst — a receipt review that fixes three fields is one snapshot.
    this.debounce = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  final LedgerRepository repository;
  final WidgetSnapshotSink sink;
  final Duration debounce;
  final DateTime Function() _clock;

  StreamSubscription<List<Object?>>? _sub;
  Timer? _timer;
  String _watchedMonth = '';

  /// Subscribe to ledger churn for the *current* month and publish once
  /// immediately (§4.2 "…and on app foreground" — start() is the cold one).
  void start() {
    _listen();
    unawaited(flush());
  }

  /// Warm resume: re-arm if the month rolled over while backgrounded,
  /// then refresh — the day the month turns, the widgets must already be
  /// right the moment the user pulls up the shade.
  void onResume() {
    _listen();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _listen() {
    final ym = yearMonthOf(_clock());
    if (ym == _watchedMonth && _sub != null) return;
    _watchedMonth = ym;
    unawaited(_sub?.cancel());
    // The row list is a churn signal only; the build re-reads what it
    // needs with the engine's own conversion rules.
    _sub = repository
        .watchMonth(ym)
        .map((r) => r.cast<Object?>())
        .listen(
          (_) => _schedule(),
          // A dead stream (db closing under restore) must not take the app;
          // resume/start re-arms it.
          onError: (Object _) {},
        );
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// Build + publish now (debounce cancelled). Snapshot failures are
  /// swallowed by design: widgets are a mirror, and a mirror that throws
  /// must not break the room. The next write or resume retries. Awaitable
  /// so tests (and the cold-start path) can join the publish.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return buildSnapshot().then(sink).catchError((Object _) {
      // Awaiters see completion, never the failure — see doc above.
    });
  }

  /// The aggregates themselves — public for tests and for the WorkManager
  /// day-rollover tick, which builds from a cold repo exactly like this.
  Future<String> buildSnapshot() async {
    final now = _clock();
    final ym = yearMonthOf(now);
    final base = Currency.resolve(await repository.baseCurrency() ?? 'USD');
    final monthIndex = (now.year - 2000) * 12 + now.month - 1;
    final budgets = await BudgetsService(
      repository,
    ).load(monthIndex, currency: base, now: now);

    // Tightest first; ties break by name so the byte output is stable.
    final envelopes =
        [
          for (final l in budgets.lines)
            WidgetEnvelope(
              name: l.name,
              remainingMinor: l.status.remainingMinor,
            ),
        ]..sort(
          (a, b) => a.remainingMinor != b.remainingMinor
              ? a.remainingMinor.compareTo(b.remainingMinor)
              : a.name.compareTo(b.name),
        );

    // No overall target → the envelopes *are* the frame (§2.1's hint-row
    // logic, same fallback the Budgets tab prints).
    final budgetSpent =
        budgets.overall?.spentMinor ??
        budgets.lines.fold<int>(0, (a, l) => a + l.status.spentMinor);
    final budgetLimit =
        budgets.overall?.effectiveLimitMinor ??
        budgets.lines.fold<int>(0, (a, l) => a + l.status.effectiveLimitMinor);

    // Whole-month total including unbudgeted categories — same engine,
    // same stored-base-amount rule as budgets_service (§3.1): never
    // re-converted, legacy FX gaps skipped rather than guessed.
    final range = monthRange(ym);
    final txs = <EngineTx>[];
    for (final t in await repository.transactionsInRange(
      range.fromDays,
      range.toDays,
    )) {
      final minor = t.currencyCode == base.code
          ? t.amountMinor
          : t.baseAmountMinor;
      if (minor == null) continue;
      txs.add(
        EngineTx(
          dateDays: t.dateDays,
          baseAmountMinor: minor,
          categoryId: t.categoryId ?? -1,
          isIncome: t.isIncome,
          isGoalTransfer: t.goalId != null,
        ),
      );
    }
    final spentMinor = BudgetEngine().spentIn(
      BudgetPeriod(BudgetPeriodType.monthly, DateTime(now.year, now.month)),
      txs,
    );

    return utf8.decode(
      encodeWidgetSnapshot(
        WidgetSnapshot(
          updatedAtMs: now.millisecondsSinceEpoch,
          yearMonth: ym,
          currency: base.code,
          spentMinor: spentMinor,
          budgetSpentMinor: budgetSpent,
          budgetLimitMinor: budgetLimit,
          envelopes: envelopes,
        ),
      ),
    );
  }
}
