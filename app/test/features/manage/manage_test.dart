// #18 — Manage screen (spec §2.4): the QuickAdd gear jumps here; Categories
// (rename / add-with-icon / drag-reorder), Base currency picker (verbatim
// §2.4 note) and About & help all live on this slice.
//
// Same drift rules as widget_test.dart: AppDatabase.close() must run INSIDE
// the test body — closing in tearDown deadlocks the fake-async zone and
// leaves drift's zero-duration markAsClosed timers pending at teardown.
import 'dart:ffi';

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> pumpApp(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
  }

  /// FAB → QuickAdd → its Manage chip → the Manage screen. The chip is the
  /// last child of a row that can overflow, so scroll it into view first.
  Future<void> openManage(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Manage'),
      find.byKey(const Key('chip-row')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Manage'));
    await tester.pumpAndSettle();
  }

  Future<void> openCategories(WidgetTester tester) async {
    await openManage(tester);
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
  }

  List<String> sectionTitles(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      (tile.title! as Text).data!,
  ];

  testWidgets('QuickAdd gear pops the sheet and lands on Manage (§2.4)', (
    tester,
  ) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openManage(tester);

      expect(find.widgetWithText(AppBar, 'Manage'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Base currency'), findsOneWidget);
      expect(find.text('About & help'), findsOneWidget);
      // The QuickAdd sheet closed instead of stacking under Manage.
      expect(find.byKey(const Key('keypad-5')), findsNothing);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('base currency picker shows the verbatim §2.4 note and drives '
      'the ledger strip', (tester) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openManage(tester);

      expect(find.text('USD'), findsOneWidget); // trailing value, unset ⇒ USD

      await tester.tap(find.text('Base currency'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Used for balances display. Existing transactions keep their own '
          'currency.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Euro'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Base currency'), findsOneWidget);
      expect(find.text('EUR'), findsOneWidget); // trailing updated

      await tester.pageBack();
      await tester.pumpAndSettle();
      // Balance strip re-read the setting: an empty month renders €0.00.
      expect(find.textContaining('€'), findsWidgets);
      expect(find.textContaining(r'$'), findsNothing);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('rename flows through to the QuickAdd chips', (tester) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openCategories(tester);

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(find.text('Rename category'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Coffee');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Food'), findsNothing);

      await tester.pageBack(); // Manage
      await tester.pumpAndSettle();
      await tester.pageBack(); // Ledger
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Coffee'), findsOneWidget);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('add category via the 4×8 icon grid lands at the end', (
    tester,
  ) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openCategories(tester);

      final before = await r.repo.categories();
      expect(before, hasLength(9)); // 7 expense + 2 income

      await tester.tap(find.byTooltip('Add expense category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pets');
      await tester.dragUntilVisible(
        find.byIcon(Icons.pets),
        find.byType(GridView),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.pets));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // Appended at the end of the EXPENSE section; db is the truth here,
      // because the list lazily builds only what the viewport needs.
      final stored = await r.repo.categories(income: false);
      expect(stored, hasLength(8));
      expect(stored.map((c) => c.name).toList()[7], 'Pets');
      // And it persists as an Icons.* key, not an IconData (§2.4 storage).
      expect(stored.map((c) => c.icon).toList()[7], 'pets');
      expect(stored.map((c) => c.name).toList().sublist(0, 7), [
        'Food',
        'Housing',
        'Transport',
        'Utilities',
        'Fun',
        'Health',
        'Other',
      ]);

      // Visible in the list after scrolling to the section's end. Scroll
      // position directly: the whole tile is a drag handle, so any gesture
      // flick would start an item-drag instead of scrolling the list.
      final expenseScrollable = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      tester
          .state<ScrollableState>(expenseScrollable.first)
          .position
          .jumpTo(600);
      await tester.pumpAndSettle();
      expect(find.text('Pets'), findsOneWidget);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('drag handle reorders within the section and persists', (
    tester,
  ) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openCategories(tester);

      expect(sectionTitles(tester).take(2), ['Food', 'Housing']);

      await tester.timedDrag(
        find.byIcon(Icons.drag_handle).first,
        const Offset(0, 72),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();

      expect(sectionTitles(tester).take(2), ['Housing', 'Food']);
      final stored = await r.repo.categories(income: false);
      expect(stored.map((c) => c.name).toList().take(2), ['Housing', 'Food']);
      // The income section never shares the drag surface (§2.4 sections) —
      // db-truth, since offscreen sliver children are not built in the tree.
      final incomeStored = await r.repo.categories(income: true);
      expect(incomeStored.map((c) => c.name).toList(), [
        'Salary',
        'Other income',
      ]);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('stored icon key overrides the ledger row icon', (tester) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);

      // One Food entry first…
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      for (final k in ['1', '2']) {
        await tester.tap(find.byKey(Key('keypad-$k')));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilterChip, 'Food'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.restaurant_outlined), findsWidgets);

      // …then re-icon the category as a plane (§2.4 rename sheet).
      await openCategories(tester);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byIcon(Icons.flight),
        find.byType(GridView),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.flight));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.flight), findsWidgets);
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
    } finally {
      await r.db.close();
    }
  });

  testWidgets('About & help explains the E1 gestures and the privacy promise', (
    tester,
  ) async {
    final r = freshRepo();
    try {
      // main() seeds on device; pumping the widget directly must too.
      await r.repo.ensureDefaults();
      await pumpApp(tester, r.repo);
      await openManage(tester);

      await tester.tap(find.text('About & help'));
      await tester.pumpAndSettle();

      expect(find.text('Local Budget'), findsOneWidget);
      expect(find.textContaining('stays on this device'), findsOneWidget);
      expect(find.text('Add an entry'), findsOneWidget);
      expect(find.text('Delete with undo'), findsOneWidget);
    } finally {
      await r.db.close();
    }
  });
}
