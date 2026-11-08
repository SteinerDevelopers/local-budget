// QA hardening, 2026-11-05 — the shared PanelAddBar (c6dde4e) replaces the
// old FABs with a text-button row on Receipts and Bills. FABs could never
// overflow; a text row can. These tests put the row on the narrow phone the
// store still supports (320 dp wide) at the a11y text scale the a11y suite
// pins (1.3×): no RenderFlex exception (any overflow fails the test through
// takeException below), and the buttons stay painted and live.
import 'dart:ffi' show DynamicLibrary;

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/panel_add_bar.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart';
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

  Future<int> seedWeekly(LedgerRepository repo, {required String name}) =>
      repo.addRule(
        name: name,
        amountMinor: 4500,
        currencyCode: 'USD',
        frequency: 'weekly',
        start: DateTime.now().subtract(const Duration(days: 14)),
        nextDue: DateTime.now(),
        dayOfWeek: DateTime.now().weekday,
        notify: false,
      );

  void tinyViewport(WidgetTester tester, double textScale) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> openHome(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LedgerScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    // Drift answers on the real event loop (same ceiling as the nav tests);
    // without this the panel below has not laid out — the very geometry we
    // want overflow-checked.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  for (final scale in const [1.0, 1.3]) {
    testWidgets('Receipts add bar survives 320 dp at $scale× text', (
      tester,
    ) async {
      tinyViewport(tester, scale);
      final (:db, :repo) = freshRepo();
      try {
        await openHome(tester, repo);
        // No capture services: the scanner half is *hidden* (never a dead
        // button), so the lone "Add receipt" must be present and live.
        expect(find.byKey(const ValueKey('receipt-add')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('receipt-add')));
        await tester.pumpAndSettle();
        expect(find.text('Save'), findsOneWidget); // QuickAdd is open
        expect(tester.takeException(), isNull);
      } finally {
        await db.close();
      }
    });

    testWidgets('Bills add bar survives 320 dp at $scale× text', (
      tester,
    ) async {
      tinyViewport(tester, scale);
      final (:db, :repo) = freshRepo();
      try {
        await seedWeekly(repo, name: 'Wifi');
        await openHome(tester, repo);
        await tester.tap(find.text('Bills'));
        await tester.pumpAndSettle();
        // Non-empty list ⇒ the shared bottom row (not the empty-state
        // button): exactly the shape Receipts wears.
        expect(find.byKey(const Key('bill-add')), findsOneWidget);
        expect(find.text('Add bill'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await db.close();
      }
    });

    testWidgets('PanelAddBar with BOTH halves fits 320 dp at $scale× text', (
      tester,
    ) async {
      // The real app only renders two halves once capture is wired; drive
      // the widget directly so the tightest shape is checked regardless.
      tinyViewport(tester, scale);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            bottomNavigationBar: PanelAddBar(
              primary: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add bill'),
              ),
              secondary: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.document_scanner_outlined, size: 20),
                label: const Text('Scan a receipt'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // FittedBox may shrink the glyphs, never hide a label.
      expect(find.text('Add bill'), findsOneWidget);
      expect(find.text('Scan a receipt'), findsOneWidget);
      // Both halves are inside the viewport, not pushed off-screen.
      expect(
        tester.getRect(find.text('Scan a receipt')).right,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
