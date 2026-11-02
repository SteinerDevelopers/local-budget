import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../quickadd/quick_add_sheet.dart';
import 'balance_strip.dart';
import 'day_label.dart';
import 'empty_month.dart';
import 'transaction_row.dart';
import 'view_models.dart';

/// Home of the app (§2.1): month switcher → balance strip → day groups → FAB.
/// Everything is derived from the drift stream; this screen only keeps paging
/// position and the QuickAdd warm state (§2.2 rule 5 lives with the caller).
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.repository});

  final LedgerRepository repository;

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

/// Default category icon (§2.1 row + §2.2 chips). #18 lets the user manage
/// categories; this stays the fallback by name.
IconData categoryIcon(String? name) => switch (name) {
  'Food' => Icons.restaurant_outlined,
  'Housing' => Icons.home_outlined,
  'Transport' => Icons.directions_bus_outlined,
  'Utilities' => Icons.bolt_outlined,
  'Fun' => Icons.movie_outlined,
  'Health' => Icons.monitor_heart_outlined,
  'Salary' => Icons.payments_outlined,
  'Other income' => Icons.trending_up,
  _ => Icons.label_outline,
};

/// Drift row → [EntryTile]; amount stays unsigned, sign is display-only (§3).
EntryTile tileFor(LedgerEntryData row) => EntryTile(
  id: row.id,
  icon: categoryIcon(row.categoryName),
  title: row.categoryName ?? 'Uncategorized',
  memo: (row.note == null || row.note!.isEmpty) ? null : row.note,
  amount: Money(row.amountMinor, Currency.resolve(row.currencyCode)),
  kind: row.isIncome ? EntryKind.income : EntryKind.expense,
);

/// Sums one month; income/expenses unsigned, the labels carry the sign (§2.1).
BalanceSummary summarizeMonth(List<LedgerEntryData> rows, Currency currency) {
  var income = 0;
  var expenses = 0;
  for (final r in rows) {
    if (r.isIncome) {
      income += r.amountMinor;
    } else {
      expenses += r.amountMinor;
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

  static final int _index0 = monthIndexOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    widget.repository.baseCurrency().then((code) {
      if (mounted) setState(() => _currency = Currency.resolve(code ?? 'USD'));
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
          CategoryOption(c.id, c.name, categoryIcon(c.name)),
      ],
      currency: _currency,
      initialKind: _warmKind,
      initialCategoryId: _warmCategoryId,
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

  /// Swipe-to-dismiss → SnackBar "Deleted / Undo" (§2.1). Undo is the only
  /// delete safety net — zero dialogs — and reuses the exact row id.
  Future<void> _delete(int id) async {
    final removed = await widget.repository.deleteEntry(id);
    if (removed == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('Deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.restoreEntry(removed),
        ),
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
      // Only FAB in the app (§2.1).
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickAdd,
        child: const Icon(Icons.add),
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
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

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
            BalanceStrip(summary: summarizeMonth(rows, widget.currency)),
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
    return SizedBox(
      // §2.1: 32 dp header row including spacing.
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
          child: Text(DayLabel.of(day), style: Tokens.labelCaps(context)),
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
      child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
    );
  }
}
