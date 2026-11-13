// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// E7 §5/§6 — the flavor gate for the Insights slice, plus the flavor-
// neutral BillPrefill seam the suggestions ride on.
//
// Free-flavor rows (the ones the CI gate runs) assert the trio is ABSENT.
// Pro rows self-skip unless the file runs with --dart-define=APP_FLAVOR=pro
// (same discipline as test/features/support/pro_flows_test.dart).
import 'dart:ffi' show DynamicLibrary;

import 'package:core/core.dart' show Currency;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/analytics/insights_view.dart';
import 'package:local_budget/features/bills/bill_editor_sheet.dart';
import 'package:local_budget/features/reports/reports_screen.dart';
import 'package:local_budget/flavor.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final isPro = appFlavor == AppFlavor.pro;
  final usd = Currency.resolve('USD');

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpReports(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReportsScreen(repository: repo),
      ),
    );
    await settle(tester);
  }

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('bill editor prefill', () {
    // The editor is a free feature; the prefill seam must hold in BOTH
    // flavors, so it runs in the plain suite.
    testWidgets('a suggestion fills name and pad, save still needs a tap', (
      tester,
    ) async {
      phoneScreen(tester);
      final r = freshRepo();
      addTearDown(r.db.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showBillEditor(
                  context,
                  repository: r.repo,
                  currency: usd,
                  categories: const [],
                  prefill: const BillPrefill(name: 'Coffee', amountMinor: 500),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('bill-name')))
            .controller!
            .text,
        'Coffee',
      );
      // 5.00 seeded into the pad as raw digits ('5', no trailing dot).
      expect(
        tester.widget<Text>(find.byKey(const Key('amount-value'))).data,
        '5',
      );
      // No category yet → Save stays locked; nothing was created.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('bill-save')))
            .onPressed,
        isNull,
      );
      expect(find.text('Coffee'), findsWidgets); // field + nowhere else yet
    });
  });

  group('free flavor', () {
    testWidgets('no Insights segment; month stepper untouched', (tester) async {
      final r = freshRepo();
      addTearDown(r.db.close);
      await pumpReports(tester, r.repo);
      expect(find.text('Insights'), findsNothing);
      expect(find.byKey(const Key('segment-insights')), findsNothing);
      // The stepper rework must not have cost the month segment anything.
      expect(find.byKey(const Key('month-prev')), findsOneWidget);
    }, skip: isPro);

    testWidgets('ProTrioGate renders nothing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ProTrioGate(child: Text('trio content'))),
        ),
      );
      expect(find.text('trio content'), findsNothing);
    }, skip: isPro);
  });

  group('pro flavor', () {
    testWidgets('segment surfaces insights with its own range chip', (
      tester,
    ) async {
      final r = freshRepo();
      addTearDown(r.db.close);
      await pumpReports(tester, r.repo);
      await tester.tap(find.byKey(const Key('segment-insights')));
      await settle(tester);
      expect(find.byKey(const Key('range-chip')), findsOneWidget);
      // The month stepper yields to the chip — one truth per window.
      expect(find.byKey(const Key('month-prev')), findsNothing);
      // Compare defaults on (§2.1); an all-zero delta still shows the card.
      expect(find.byKey(const Key('delta-card')), findsOneWidget);
      // The footer sits past the lazily built viewport — drag until real.
      await tester.dragUntilVisible(
        find.text('No steady monthly charges in this range.'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(
        find.text('No steady monthly charges in this range.'),
        findsOneWidget,
      );
    }, skip: !isPro);

    testWidgets('compare switch retires the delta card', (tester) async {
      final r = freshRepo();
      addTearDown(r.db.close);
      await pumpReports(tester, r.repo);
      await tester.tap(find.byKey(const Key('segment-insights')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('compare-switch')));
      await settle(tester);
      expect(find.byKey(const Key('delta-card')), findsNothing);
      // Chart + suggestions stay; only the comparison layer left.
      expect(find.text('Steady monthly charges'), findsOneWidget);
    }, skip: !isPro);
  });
}
