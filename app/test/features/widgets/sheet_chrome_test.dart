// Device feedback 2026-11-04 pm — "seeing similar behavior on other add
// screens for bills, budgets, etc…": 3-button devices painted Save rows
// underneath the system nav bar, and phones held sideways clipped the
// keypad mid-row. QuickAdd already pins this contract (its sheet is the
// reference grammar); these tests pin the SAME contract for every sheet
// that borrows its chrome: the action row clears the nav bar, a larger
// system font grows the sheet budget instead of spilling pixels, and the
// short landscape screen splits fields and pad instead of overflowing.
import 'dart:ffi' show DynamicLibrary;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/bills/bill_detail_sheet.dart';
import 'package:local_budget/features/bills/bill_editor_sheet.dart';
import 'package:local_budget/features/bills/bills_service.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/budgets/budgets_service.dart';
import 'package:local_budget/features/budgets/budgets_tab.dart' show BudgetsTab;
import 'package:local_budget/features/budgets/limit_editor_sheet.dart';
import 'package:local_budget/features/goals/goal_detail_sheet.dart';
import 'package:local_budget/features/goals/goal_editor_sheet.dart';
import 'package:local_budget/features/goals/goals_service.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf;
import 'package:local_budget/features/manage/category_edit_sheet.dart';
import 'package:local_budget/features/manage/passphrase_sheet.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final thisMonth = monthIndexOf(DateTime.now());
  const navBar = 48.0; // a 3-button system bar on a 360×800 phone
  const phoneH = 800.0;

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  void phoneView(
    WidgetTester tester, {
    double w = 360,
    double h = phoneH,
    double nav = 0,
    double scale = 1,
  }) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (nav > 0) {
      tester.view.viewPadding = FakeViewPadding(bottom: nav);
      addTearDown(tester.view.resetViewPadding);
    }
    if (scale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
  }

  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The widget's bottom edge must sit above the nav bar strip.
  void expectClearsNavBar(WidgetTester tester, Finder finder) {
    expect(
      tester.getRect(finder).bottom,
      lessThanOrEqualTo(phoneH - navBar + 0.01),
    );
  }

  group('add-sheet chrome (device feedback 2026-11-04 pm)', () {
    testWidgets('bill editor: Save clears the nav bar portrait', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showBillEditor(
            context,
            repository: r.repo,
            currency: usd,
            categories: const [],
          ),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.byKey(const Key('bill-save')));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('bill editor: landscape splits, nothing overflows', (
      tester,
    ) async {
      phoneView(tester, w: 800, h: 360);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showBillEditor(
            context,
            repository: r.repo,
            currency: usd,
            categories: const [],
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('bill-save')), findsOneWidget);
      } finally {
        await r.db.close();
      }
    });

    testWidgets('bill editor: 1.3× text grows the sheet, not the overflow', (
      tester,
    ) async {
      phoneView(tester, nav: navBar, scale: 1.3);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showBillEditor(
            context,
            repository: r.repo,
            currency: usd,
            categories: const [],
          ),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.byKey(const Key('bill-save')));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('goal editor: Create clears the nav bar; landscape fits', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showGoalEditor(context, repository: r.repo),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.byKey(const Key('goal-save')));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('goal editor: landscape has no overflow', (tester) async {
      phoneView(tester, w: 800, h: 360);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showGoalEditor(context, repository: r.repo),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await r.db.close();
      }
    });

    testWidgets('limit editor: Save clears the nav bar', (tester) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        final snap = await BudgetsService(r.repo).load(thisMonth);
        await open(
          tester,
          (context) => showLimitEditor(
            context,
            repository: r.repo,
            snapshot: snap,
            monthIndex: thisMonth,
          ),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.byKey(const Key('limit-save')));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('limit editor: landscape splits, nothing overflows', (
      tester,
    ) async {
      phoneView(tester, w: 800, h: 360);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        final snap = await BudgetsService(r.repo).load(thisMonth);
        await open(
          tester,
          (context) => showLimitEditor(
            context,
            repository: r.repo,
            snapshot: snap,
            monthIndex: thisMonth,
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await r.db.close();
      }
    });

    testWidgets('budgets sheet: tab content stops above the nav bar', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) => showBudgetsSheet(
            context,
            repository: r.repo,
            monthIndex: thisMonth,
            currency: usd,
          ),
        );
        expect(tester.takeException(), isNull);
        // The Rollover row is the last thing the Budgets tab paints; its
        // region ended underneath the 3-button bar.
        expectClearsNavBar(tester, find.byType(BudgetsTab));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('category editor: Add button clears the nav bar', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.ensureDefaults();
        await open(
          tester,
          (context) =>
              showCategoryEdit(context, repository: r.repo, income: false),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.widgetWithText(FilledButton, 'Add'));
      } finally {
        await r.db.close();
      }
    });
  });

  // Wave 2 of the same device report ("Some other screens with similar
  // issue", 2026-11-04 pm, passphrase screenshot): flow and detail
  // sheets that padded by viewInsets alone sit flush with the physical
  // bottom whenever no keyboard is up, so their last row — the action
  // row — lands in the 3-button strip. Same gate as the add sheets.
  group('flow & detail sheet chrome (device feedback 2026-11-04 pm)', () {
    testWidgets('passphrase sheet: Continue clears the nav bar', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      await open(
        tester,
        (context) => showPassphraseSheet(
          context,
          title: 'Choose a passphrase for this backup',
          withConfirm: true,
        ),
      );
      expect(tester.takeException(), isNull);
      expectClearsNavBar(tester, find.byKey(const Key('passphrase-next')));
    });

    testWidgets('goal keypad: Confirm clears the nav bar', (tester) async {
      phoneView(tester, nav: navBar);
      await open(
        tester,
        (context) => showAmountSheet(
          context,
          currency: usd,
          title: 'Add to goal',
          cta: 'Add',
        ),
      );
      expect(tester.takeException(), isNull);
      expectClearsNavBar(tester, find.byKey(const Key('goal-amount-confirm')));
    });

    testWidgets('goal detail: Withdraw and Deposit clear the nav bar', (
      tester,
    ) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.addGoal(
          name: 'Emergency fund',
          currencyCode: 'USD',
          targetMinor: 500000,
        );
        final goals = await loadGoalLines(r.repo);
        await open(
          tester,
          (context) =>
              showGoalDetail(context, repository: r.repo, line: goals.single),
        );
        expect(tester.takeException(), isNull);
        expectClearsNavBar(tester, find.byKey(const Key('goal-withdraw')));
        expectClearsNavBar(tester, find.byKey(const Key('goal-deposit')));
      } finally {
        await r.db.close();
      }
    });

    testWidgets('bill detail: Delete rule clears the nav bar', (tester) async {
      phoneView(tester, nav: navBar);
      final r = freshRepo();
      try {
        await r.repo.addRule(
          name: 'Rent',
          amountMinor: 90000,
          currencyCode: 'USD',
          frequency: 'monthly',
          start: DateTime(2026, 1, 15),
          nextDue: DateTime(2026, 11, 15),
          dayOfMonth: 15,
          notify: false,
        );
        final lines = await loadBillLines(
          r.repo,
          now: DateTime(2026, 11, 4, 12),
        );
        await open(
          tester,
          (context) => showBillDetail(
            context,
            repository: r.repo,
            line: lines.single,
            categories: const [],
          ),
        );
        expect(tester.takeException(), isNull);
        // Delete rule is the last thing this sheet paints.
        expectClearsNavBar(tester, find.byKey(const Key('bill-delete')));
      } finally {
        await r.db.close();
      }
    });
  });
}
