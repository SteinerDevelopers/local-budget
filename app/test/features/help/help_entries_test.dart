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

// #9 — E8 §3: Help is a first-class destination, not a buried link. The
// month header, the Budgets sheet and the Reports bar each carry a "?"
// that lands on the same offline HelpScreen. (drift rule: close the db
// INSIDE the test body.)
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/features/budgets/budgets_sheet.dart';
import 'package:local_budget/features/help/help_screen.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart'
    show monthIndexOf;
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> pumpApp(WidgetTester tester, LedgerRepository repo) async {
    await tester.pumpWidget(LocalBudgetApp(repository: repo));
    await tester.pumpAndSettle();
  }

  testWidgets('the month header opens Help', (tester) async {
    final (:db, :repo) = freshRepo();
    await pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('help-open')));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('Scanning receipts'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsNothing);
    await db.close();
  });

  testWidgets('the month header opens Reports through Help and back', (
    tester,
  ) async {
    final (:db, :repo) = freshRepo();
    await pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('reports-open')));
    await tester.pumpAndSettle();
    // Reports carries its own entrance so no screen dead-ends.
    await tester.tap(find.byKey(const Key('reports-help')));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    await db.close();
  });

  testWidgets('the Budgets sheet opens Help', (tester) async {
    final (:db, :repo) = freshRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBudgetsSheet(
                context,
                repository: repo,
                monthIndex: monthIndexOf(DateTime.now()),
                currency: usd,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget-help')));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    await db.close();
  });
}
