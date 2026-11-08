// #35 — the Bills tab end-to-end at the widget level (design e3 §2.3/§3.4):
// empty state, the rule editor, mark-paid writing a real transaction and
// advancing the cursor, delete, overdue styling, and the notification-tap
// focus path (`focusBillId`). BillNotifier is never bootstrapped here, so
// every schedule/cancel is a no-op — no method channel in tests (§5).
//
// Same drift rules as manage_test.dart: close the db INSIDE the test body.
import 'dart:ffi' show DynamicLibrary;

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/bills/bills_service.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/capture_services.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf;
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final now = DateTime.now();
  final thisMonth = monthIndexOf(now);
  // Wall-clock-safe calendar arithmetic (day 0 normalizes across months).
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final far = DateTime(now.year, now.month, now.day + 10);

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  /// Modal-sheet settle: same discipline as budgets_sheet_test — pop +
  /// parent reload needs a beat after the animation.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  /// A weekly rule that falls due on [due] (dayOfWeek pinned to match).
  Future<int> seedWeekly(
    LedgerRepository repo, {
    required String name,
    required DateTime due,
    int amountMinor = 4500,
    bool notify = false,
    int? categoryId,
  }) => repo.addRule(
    name: name,
    amountMinor: amountMinor,
    currencyCode: 'USD',
    frequency: 'weekly',
    start: DateTime(due.year, due.month, due.day - 14),
    nextDue: due,
    dayOfWeek: due.weekday,
    notify: notify,
    categoryId: categoryId,
  );

  Future<void> openSheet(
    WidgetTester tester,
    LedgerRepository repo, {
    int? focusBillId,
    CaptureServices? capture,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBudgetsSheet(
                context,
                repository: repo,
                monthIndex: thisMonth,
                currency: usd,
                focusBillId: focusBillId,
                capture: capture,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> openBillsTab(
    WidgetTester tester,
    LedgerRepository repo, {
    CaptureServices? capture,
  }) async {
    await openSheet(tester, repo, capture: capture);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('Bills'),
      ),
    );
    await settle(tester);
  }

  /// The editor lives in a ~92% sheet; a phone-shaped surface is what the
  /// keypad + form were sized for (design e3 §2.3).
  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Bills tab (#35)', () {
    testWidgets('empty state offers the first bill (§2.3)', (tester) async {
      final (:db, :repo) = freshRepo();
      await openBillsTab(tester, repo);
      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.byKey(const Key('bill-add-empty')), findsOneWidget);
      await db.close();
    });

    testWidgets('editor adds a rule; row appears', (tester) async {
      phoneScreen(tester);
      final (:db, :repo) = freshRepo();
      final streaming = await repo.addCategory('Streaming');
      await openBillsTab(tester, repo);
      await tapKey(tester, const Key('bill-add-empty'));

      // Save is inert until name + amount + category are all present.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('bill-save')))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(const Key('bill-name')), 'Netflix');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bill-categories')),
          matching: find.text('Streaming'),
        ),
      );
      await tester.pump();
      for (final d in ['1', '2', '0', '0']) {
        await tester.tap(find.byKey(Key('keypad-$d')));
        await tester.pump();
      }
      await tapKey(tester, const Key('bill-save'));

      expect(find.text('Netflix'), findsOneWidget);
      final r = (await repo.rules()).single;
      expect(r.name, 'Netflix');
      expect(r.amountMinor, 120000); // keypad digits are MAJOR units
      expect(r.currencyCode, 'USD');
      expect(r.categoryId, streaming);
      expect(r.frequency, 'monthly');
      expect(r.dayOfMonth, now.day);
      expect(r.notify, isTrue);
      // First occurrence is today: start month, day-of-month = today.
      expect(
        dayFromEpoch(r.nextDueMs ~/ 86400000),
        DateTime(now.year, now.month, now.day),
      );
      await db.close();
    });

    testWidgets('weekly mode exposes day chips', (tester) async {
      phoneScreen(tester);
      final (:db, :repo) = freshRepo();
      await openBillsTab(tester, repo);
      await tapKey(tester, const Key('bill-add-empty'));
      await tester.tap(find.text('Weekly'));
      await settle(tester);
      expect(find.byKey(const Key('dow-3')), findsOneWidget);
      expect(find.byKey(const Key('dom-1')), findsNothing);
      await tester.tap(find.text('Yearly'));
      await settle(tester);
      // The day row is a horizontal ListView — assert the built prefix.
      expect(find.byKey(const Key('dom-3')), findsOneWidget);
      expect(find.byKey(const Key('dow-3')), findsNothing);
      await db.close();
    });

    testWidgets('mark paid writes a ledger entry and advances the rule', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      // Overdue on purpose: yesterday's occurrence.
      final id = await seedWeekly(repo, name: 'Wifi', due: yesterday);
      await openBillsTab(tester, repo);
      await tapKey(tester, Key('bill-row-$id'));
      expect(find.text('Wifi'), findsWidgets); // row + detail title
      await tapKey(tester, const Key('bill-mark-paid'));

      // §3.4 — one manual expense back-dated to the occurrence's own day.
      final txs = await repo.transactionsInRange(
        epochDayOf(yesterday) - 1,
        epochDayOf(now) + 1,
      );
      final tx = txs.singleWhere((t) => t.note == 'Bill: Wifi');
      expect(tx.amountMinor, 4500);
      expect(tx.dateDays, epochDayOf(yesterday));

      // The cursor advanced exactly one week from the PAID occurrence.
      final r = (await repo.rules()).single;
      expect(dayFromEpoch(r.nextDueMs ~/ 86400000), _addDays(yesterday, 7));
      // And the tab shows the fresh due date, no longer overdue.
      expect(find.text('Wifi'), findsOneWidget);
      expect(
        billDueState(r.nextDueMs ~/ 86400000, epochDayOf(now)),
        isNot(BillDueState.overdue),
      );
      await db.close();
    });

    testWidgets('delete asks once, then the rule is gone', (tester) async {
      final (:db, :repo) = freshRepo();
      final id = await seedWeekly(repo, name: 'Old Plan', due: yesterday);
      await openBillsTab(tester, repo);
      await tapKey(tester, Key('bill-row-$id'));
      await tapKey(tester, const Key('bill-delete'));
      expect(find.text('Delete this bill?'), findsOneWidget);
      await tapKey(tester, const Key('bill-delete-confirm'));
      expect(find.text('No bills yet'), findsOneWidget);
      expect(await repo.rules(), isEmpty);
      await db.close();
    });

    testWidgets('overdue leads in error color; far dates are muted (§2.3)', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final lateId = await seedWeekly(repo, name: 'Late', due: yesterday);
      final farId = await seedWeekly(repo, name: 'Far', due: far);
      await openBillsTab(tester, repo);
      final scheme = AppTheme.light().colorScheme;

      Color dueColor(int bill) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('bill-row-$bill')),
              matching: find.textContaining('Due'),
            ),
          )
          .style!
          .color!;
      expect(dueColor(lateId), scheme.error);
      expect(dueColor(farId), scheme.onSurfaceVariant);
      await db.close();
    });

    testWidgets('edit rule prefills and updates', (tester) async {
      phoneScreen(tester);
      final (:db, :repo) = freshRepo();
      final home = await repo.addCategory('Home');
      final id = await seedWeekly(
        repo,
        name: 'Wifi',
        due: far,
        amountMinor: 4500,
        categoryId: home,
      );
      await openBillsTab(tester, repo);
      await tapKey(tester, Key('bill-row-$id'));
      await tapKey(tester, const Key('bill-edit'));
      expect(find.text('Save changes'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('bill-name')))
            .controller!
            .text,
        'Wifi',
      );
      await tester.enterText(find.byKey(const Key('bill-name')), 'Wifi Fiber');
      await tapKey(tester, const Key('bill-save'));
      expect(find.text('Wifi Fiber'), findsOneWidget);
      expect((await repo.rules()).single.name, 'Wifi Fiber');
      await db.close();
    });

    testWidgets('focusBillId lands straight on the detail (§5 tap path)', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      final id = await seedWeekly(repo, name: 'FromNotification', due: now);
      await openSheet(tester, repo, focusBillId: id);
      await settle(tester);
      expect(find.text('FromNotification'), findsWidgets);
      expect(find.byKey(const Key('bill-mark-paid')), findsOneWidget);
      await db.close();
    });

    testWidgets(
      'a >365-day bill surfaces "Paused?" and resume fixes it (§3.4)',
      (tester) async {
        final (:db, :repo) = freshRepo();
        final stale = DateTime(now.year, now.month, now.day - 400);
        final id = await seedWeekly(repo, name: 'Dormant', due: stale);
        await openBillsTab(tester, repo);
        final row = find.byKey(Key('bill-row-$id'));
        expect(
          find.descendant(of: row, matching: find.textContaining('Paused?')),
          findsOneWidget,
        );

        await tapKey(tester, Key('bill-row-$id'));
        expect(find.byKey(const Key('bill-resume')), findsOneWidget);
        expect(find.byKey(const Key('bill-mark-paid')), findsNothing);
        await tapKey(tester, const Key('bill-resume'));

        final r = (await repo.rules()).single;
        final dueEpoch = r.nextDueMs ~/ 86400000;
        expect(dueEpoch, greaterThanOrEqualTo(epochDayOf(now))); // from today
        expect(dueEpoch, lessThanOrEqualTo(epochDayOf(now) + 6)); // weekly
        expect(find.textContaining('Paused?'), findsNothing);
        expect(find.textContaining('Due '), findsWidgets);
        await db.close();
      },
    );

    testWidgets('no capture services — no document button, no dead end', (
      tester,
    ) async {
      final (:db, :repo) = freshRepo();
      await openBillsTab(tester, repo);
      expect(find.byKey(const Key('bill-add-empty')), findsOneWidget);
      expect(find.text('Scan a bill'), findsNothing);
      await db.close();
    });

    testWidgets('a bill photo prefills the editor, saving writes the rule', (
      tester,
    ) async {
      phoneScreen(tester);
      final (:db, :repo) = freshRepo();
      final food = await repo.addCategory('Food');
      expect(food, isNonZero);
      await openBillsTab(tester, repo, capture: docServices(lines: billLines));
      expect(find.text('Scan a bill'), findsOneWidget);
      await tester.tap(find.text('Scan a bill'));
      await settle(tester);
      await tester.tap(find.text('Photos'));
      await settle(tester);
      expect(find.byKey(const Key('bill-prefill-note')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('bill-name')))
            .controller!
            .text,
        'ACME ELECTRIC',
      );
      // The keypad seeds from minor units: frac 0 shows bare '84'.
      expect(find.text('84'), findsWidgets);

      // The document alone saves nothing; picking a category + Save does,
      // and the tab reloads through onChanged.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bill-categories')),
          matching: find.text('Food'),
        ),
      );
      await tester.pump();
      await tapKey(tester, const Key('bill-save'));
      expect(find.text('ACME ELECTRIC'), findsOneWidget);
      final r = (await repo.rules()).single;
      expect(r.name, 'ACME ELECTRIC');
      expect(r.amountMinor, 8400);
      await db.close();
    });

    testWidgets('a statement photo sends you to the wizard, not a bill', (
      tester,
    ) async {
      phoneScreen(tester);
      final (:db, :repo) = freshRepo();
      await openBillsTab(
        tester,
        repo,
        capture: docServices(lines: statementLines),
      );
      await tester.tap(find.text('Scan a bill'));
      await settle(tester);
      await tester.tap(find.text('Photos'));
      await settle(tester);
      expect(find.textContaining('reads like a statement'), findsOneWidget);
      expect(await repo.rules(), isEmpty);
      await db.close();
    });

    testWidgets('pause archives a stale rule, nothing deleted', (tester) async {
      final (:db, :repo) = freshRepo();
      final stale = DateTime(now.year, now.month, now.day - 400);
      final id = await seedWeekly(repo, name: 'Dormant', due: stale);
      await openSheet(tester, repo, focusBillId: id);
      await settle(tester);
      expect(find.byKey(const Key('bill-pause')), findsOneWidget);
      await tapKey(tester, const Key('bill-pause'));

      expect(find.text('No bills yet'), findsOneWidget);
      expect(await repo.rules(), isEmpty);
      final archived = (await repo.rules(includeArchived: true)).single;
      expect(archived.archived, isTrue);
      await db.close();
    });
  });
}

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// E11 seam copies from data_flows_test: opaque bytes in, canned OCR lines
/// out — routing and drafting are the real path.
class DocIntake implements CaptureIntake {
  @override
  bool get hasScreenshotRow => false;

  @override
  Future<CapturePick?> pick(CaptureChoice choice) async =>
      CapturePick(bytes: Uint8List.fromList([0]), choice: choice);
}

class LinesExtractor implements TextExtractor {
  LinesExtractor({this.lines = const []});
  final List<String> lines;

  @override
  Future<List<String>> extractText(Uint8List image) async => lines;
}

CaptureServices docServices({List<String> lines = const []}) => CaptureServices(
  intake: DocIntake(),
  extractor: LinesExtractor(lines: lines),
);

/// Same fixtures the wizard tests use (ACME bill; a routed statement).
const billLines = [
  'ACME ELECTRIC',
  'AMOUNT DUE 84.00',
  'PAYMENT DUE DATE 01/15/2027',
];

/// ≥ kStatementMinRows date+amount lines, no bill signature — the router
/// sends this to the statement preview, so the tab must route onward.
const statementLines = [
  '12/01/2026 CORNER MARKET 24.60 1,204.60',
  '12/03/2026 SALARY CREDIT 2,400.00 3,604.60',
  '12/05/2026 UTILITY AUTO PAY 84.00 3,520.60',
  '12/08/2026 COFFEE HOUSE 4.75 3,515.85',
];
