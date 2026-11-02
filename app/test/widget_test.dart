// End-to-end widget test of the #17 slice: drift (in-memory) → Ledger (§2.1)
// → QuickAdd (§2.2) → row + totals → swipe delete → Undo.
//
// drift runs SQLite synchronously on the same isolate, so plain awaits settle
// inside fake async. One caveat: AppDatabase.close() must run INSIDE the test
// body — closing in tearDown deadlocks on zone-bound stream controllers and
// wedges flutter_tester at exit (no output, no timeout).
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart';
import 'package:local_budget/features/ledger/transaction_row.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  // CI images carry libsqlite3.so.0 (SONAME); the -dev symlink is absent
  // (same override as packages/data tests).
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  /// Opens a fresh database + repository for one test; the caller closes it
  /// inside the test body (see header note).
  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> pumpApp(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
  }

  Future<void> pressKeys(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      final key = k == '.' ? 'dot' : k;
      await tester.tap(find.byKey(Key('keypad-$key')));
      await tester.pump();
    }
  }

  Future<void> quickAdd(
    WidgetTester tester,
    LedgerRepository repo,
    String keys,
    String chip,
  ) async {
    await tester.tap(find.byKey(const ValueKey('fab-quickadd')));
    await tester.pumpAndSettle(); // categories() lands synchronously
    await pressKeys(tester, keys);
    await tester.tap(find.widgetWithText(FilterChip, chip));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(); // addEntry + stream re-emission + close
  }

  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5)); // above the sheet → barrier
    await tester.pumpAndSettle();
  }

  final title = monthTitle(monthIndexOf(DateTime.now()));
  final usd = Currency.resolve('USD');

  testWidgets('cold month: header, zero strip, empty state (§2.1)', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    try {
      await repo.ensureDefaults();
      await pumpApp(tester, repo);

      expect(find.text(title), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);
      // Income / expenses / net all zero in the device base currency.
      expect(find.text(r'$0.00'), findsNWidgets(3));
      // Newest month opens first; a future month is one tap away.
      expect(find.byTooltip('Next month'), findsOneWidget);
    } finally {
      await db.close();
    }
  });

  testWidgets('QuickAdd saves a row, the strip updates, warm reopen (§2.2)', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    try {
      await repo.ensureDefaults();
      await pumpApp(tester, repo);
      await quickAdd(tester, repo, '12.40', 'Food');

      // Row landed: category title, day header, signed amount (§2.1 sort puts
      // it on top; expense renders U+2212 on onSurface).
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      // Strip expenses unsigned; the signed string appears twice — row + net.
      expect(find.text(r'$12.40'), findsOneWidget);
      expect(find.text('\u2212\$12.40'), findsNWidgets(2));

      // Warm reopen: same kind, same chip preselected (§2.2 rule 5).
      await tester.tap(find.byKey(const ValueKey('fab-quickadd')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Food'))
            .selected,
        isTrue,
      );
      await dismissSheet(tester);
      expect(find.text('Food'), findsOneWidget);
    } finally {
      await db.close();
    }
  });

  testWidgets('swipe deletes with SnackBar Undo that restores (§2.1)', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    try {
      await repo.ensureDefaults();
      await pumpApp(tester, repo);
      await quickAdd(tester, repo, '6.40', 'Transport');
      expect(find.byType(TransactionRow), findsOneWidget);

      // 600 px in 100 ms ≈ 6000 px/s: a fling past Dismissible's velocity
      // gate; confirmDismiss awaits deleteEntry before returning true.
      await tester.timedDrag(
        find.byType(TransactionRow),
        const Offset(-600, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TransactionRow), findsNothing);
      expect(find.text('No transactions yet'), findsOneWidget); // month empty
      expect(find.text('Deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle(); // restoreEntry + stream re-emission

      expect(find.byType(TransactionRow), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      // Row and net strip both render −$6.40 after the restore.
      expect(find.text('\u2212\$6.40'), findsNWidgets(2));
    } finally {
      await db.close();
    }
  });

  testWidgets('income entries sum apart from expenses (§2.1 strip)', (
    tester,
  ) async {
    final (db: db, repo: repo) = freshRepo();
    try {
      await repo.ensureDefaults();
      final foodId = (await repo.categories(income: false)).first.id;
      final salaryId = (await repo.categories(income: true)).first.id;
      await repo.addEntry(
        date: DateTime.now(),
        amount: Money(240000, usd),
        isIncome: true,
        categoryId: salaryId,
      );
      await repo.addEntry(
        date: DateTime.now(),
        amount: Money(5000, usd),
        isIncome: false,
        categoryId: foodId,
      );
      await pumpApp(tester, repo);

      expect(find.text(r'$2,400.00'), findsOneWidget); // income
      expect(find.text(r'$50.00'), findsOneWidget); // expenses
      expect(find.text(r'$2,350.00'), findsOneWidget); // net stays positive
      // Signed amounts on the rows: +income primary, −expense onSurface.
      expect(find.text('+\$2,400.00'), findsOneWidget);
      expect(find.text('\u2212\$50.00'), findsOneWidget);
    } finally {
      await db.close();
    }
  });
}
