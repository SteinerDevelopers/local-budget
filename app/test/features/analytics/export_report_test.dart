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

// E7 §2.3 — the export entry point and share flow. Free builds must not
// contain the row at all (a gate, not a teaser); pro builds must put real
// file bytes — a PDF and a zip — through the same Io seam the CSV uses.
// Pro rows self-skip in the free suite and the free row self-skips under
// --dart-define=APP_FLAVOR=pro, the discipline of insights_gate_test.
import 'dart:ffi' show DynamicLibrary;
import 'dart:typed_data';

import 'package:core/core.dart' show Currency, Money, TransactionSource;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/analytics/insights_view.dart';
import 'package:local_budget/features/manage/io.dart';
import 'package:local_budget/flavor.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

/// Captures share hand-offs instead of touching a device (§3 seam).
class FakeIo implements Io {
  final shared = <(Uint8List bytes, String name)>[];

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async => null;

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    shared.add((bytes, fileName));
  }

  @override
  Future<Uri?> saveFile({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
  }) async => Uri.parse('content://fake/saved/$fileName');
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final isPro = appFlavor == AppFlavor.pro;
  final usd = Currency.resolve('USD');
  final now = DateTime.now();

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapReal(WidgetTester tester, Finder f) =>
      tester.runAsync(() async {
        await tester.ensureVisible(f);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(f);
        await tester.pumpAndSettle(); // sheet open/pop animation is fake-time
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pumpAndSettle();
      });

  Future<void> waitReal(WidgetTester tester, Future<bool> Function() done) =>
      tester.runAsync(() async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (await done()) return;
        }
      });

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// An in-memory ledger with spend, income and the escaping-test merchant,
  /// seeded into the month the (wall-clock) view defaults to.
  Future<(AppDatabase, LedgerRepository)> seed() async {
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    final food = await repo.addCategory('Food');
    final rent = await repo.addCategory('Rent');
    final pay = await repo.addCategory('Pay', isIncome: true);
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: DateTime(now.year, now.month, 4),
      amount: Money(1234, usd),
      source: TransactionSource.manual,
      categoryId: food,
      merchant: 'Café & "Sons"',
    );
    await repo.addTransaction(
      accountId: acc.id,
      date: DateTime(now.year, now.month, 3),
      amount: Money(90000, usd),
      source: TransactionSource.manual,
      categoryId: rent,
    );
    await repo.addTransaction(
      accountId: acc.id,
      date: DateTime(now.year, now.month, 1),
      amount: Money(200000, usd),
      source: TransactionSource.manual,
      categoryId: pay,
      isIncome: true,
    );
    return (db, repo);
  }

  Future<FakeIo> pumpInsights(WidgetTester tester, LedgerRepository repo) async {
    final io = FakeIo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InsightsView(repository: repo, io: io)),
      ),
    );
    await settle(tester);
    return io;
  }

  group('free flavor', () {
    testWidgets('the export row is not part of the free build', (tester) async {
      phoneScreen(tester);
      final (db, repo) = await seed();
      addTearDown(db.close);
      await pumpInsights(tester, repo);
      // Scroll to the very bottom so "absent" means absent, not unbuilt.
      await tester.dragUntilVisible(
        find.text('No steady monthly charges in this range.'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('export-report')), findsNothing);
      expect(find.text('Export report'), findsNothing);
    }, skip: isPro);
  });

  group('pro flavor', () {
    Future<void> openSheet(WidgetTester tester) =>
        tapReal(tester, find.byKey(const Key('export-report')));

    testWidgets('PDF report shares real PDF bytes', (tester) async {
      phoneScreen(tester);
      final (db, repo) = await seed();
      addTearDown(db.close);
      final io = await pumpInsights(tester, repo);

      await openSheet(tester);
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel workbook'), findsOneWidget);
      await tapReal(tester, find.byKey(const Key('export-pdf')));

      await waitReal(tester, () async => io.shared.isNotEmpty);
      await tester.pumpAndSettle();
      expect(io.shared, hasLength(1));
      final (bytes, name) = io.shared.single;
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(
        name,
        matches(RegExp(r'^budget-report-\d{4}-\d{2}-\d{2}\.pdf$')),
      );
      expect(find.text('PDF report ready to share as $name'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // let the snack expire
      await tester.pumpAndSettle();
    }, skip: !isPro);

    testWidgets('Excel workbook shares real zip bytes', (tester) async {
      phoneScreen(tester);
      final (db, repo) = await seed();
      addTearDown(db.close);
      final io = await pumpInsights(tester, repo);

      await openSheet(tester);
      await tapReal(tester, find.byKey(const Key('export-xlsx')));

      await waitReal(tester, () async => io.shared.isNotEmpty);
      await tester.pumpAndSettle();
      expect(io.shared, hasLength(1));
      final (bytes, name) = io.shared.single;
      expect(bytes[0], 0x50); // 'P'
      expect(bytes[1], 0x4B); // 'K'
      expect(
        name,
        matches(RegExp(r'^budget-report-\d{4}-\d{2}-\d{2}\.xlsx$')),
      );
      expect(
        find.text('Excel workbook ready to share as $name'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5)); // let the snack expire
      await tester.pumpAndSettle();
    }, skip: !isPro);
  });
}
