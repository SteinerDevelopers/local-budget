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

// E11 M4 — the owner's whole document journey in one test, from the ledger
// tab to new rows in the database: Manage → Import → *Photo or PDF*
// → photo of a bank statement → Preview that flags the row already in the
// account → commit → ledger +N. Only OCR and the photo picker are faked;
// routing, parsing, dedupe, Preview, commit and the ledger query are the
// shipped code path (E11 §5, spec §6 journey).
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart' show Currency, Money, TransactionSource;
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';
import 'package:local_budget/features/capture/capture_services.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class _DocIntake implements CaptureIntake {
  @override
  bool get hasScreenshotRow => false;

  @override
  Future<CapturePick?> pick(CaptureChoice choice) async =>
      CapturePick(bytes: Uint8List.fromList([0]), choice: choice);
}

class _LinesExtractor implements TextExtractor {
  _LinesExtractor(this.lines);
  final List<String> lines;

  @override
  Future<List<String>> extractText(Uint8List image) async => lines;
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  // A dot-decimal statement with a running-balance column — the same
  // shape the E11 §6 corpus renders, typed out so the journey reads as
  // the document a tester would photograph.
  const statementLines = [
    'NORTHFIELD CREDIT UNION',
    'ACCOUNT 4471 0296',
    'DATE DESCRIPTION AMOUNT BALANCE',
    '12/01/2026 CORNER FOOD MART 24.60 1,780.00',
    '12/03/2026 PAYROLL DEPOSIT +2,400.00 4,180.00',
    '12/05/2026 CITY TRANSIT CARD 38.00 4,142.00',
    '12/08/2026 PHOENIX PHARMACY 15.25 4,126.75',
  ];

  testWidgets('photo of a statement lands on the ledger with one duplicate caught', (
    tester,
  ) async {
    final docs = Directory.systemTemp.createTempSync('lzb_journey');
    final db = AppDatabase.openFile('${docs.path}/localbudget.sqlite');
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();
    final account = await repo.defaultAccount();

    // The owner already typed the food-mart trip last week — QuickAdd,
    // same day and amount. The dedupe tuple must recognise it on import.
    await repo.addTransaction(
      accountId: account.id,
      date: DateTime(2026, 12, 1),
      amount: Money(2460, Currency.resolve('USD')),
      source: TransactionSource.manual,
      merchant: 'Corner Food Mart',
    );

    await tester.pumpWidget(
      LocalBudgetApp(
        repository: repo,
        db: db,
        docsDir: docs,
        capture: CaptureServices(
          intake: _DocIntake(),
          extractor: _LinesExtractor(statementLines),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ledger → Manage → Import.
    await tester.tap(find.byKey(const Key('manage-open')));
    await tester.pumpAndSettle();
    final importRow = find.byKey(const Key('import-statement'));
    await tester.scrollUntilVisible(
      importRow,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(importRow);
    await tester.pumpAndSettle();

    // The document row → sheet → one photo; the fake picker and OCR do
    // the rest. No column mapping: scanned lines arrive pre-parsed.
    await tester.tap(find.byKey(const Key('import-pick-document')));
    await tester.pumpAndSettle();
    expect(find.text('Scan a bill or statement'), findsOneWidget);
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    // Preview: every scanned row listed, the known one marked, the
    // shared-row caveat shown (§5 copy).
    expect(find.byKey(const Key('import-document-note')), findsOneWidget);
    expect(
      find.textContaining(
        'Scanned rows are checked against what is already in the account.',
      ),
      findsOneWidget,
    );
    for (var i = 0; i < statementLines.length - 3; i++) {
      expect(find.byKey(Key('import-row-$i')), findsOneWidget);
    }
    expect(find.textContaining('already imported'), findsOneWidget);

    // The duplicate starts unchecked; the owner imports the other three.
    expect(find.byKey(const Key('import-commit')), findsOneWidget);
    expect(find.text('Import 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-commit')));
    await tester.pumpAndSettle();
    expect(find.text('Imported 3 transactions'), findsOneWidget);

    // Done → back out, and the ledger itself carries the new rows: three
    // statement-import transactions in December (the dup stays one row).
    await tester.tap(find.byKey(const Key('import-close')));
    await tester.pumpAndSettle();
    final december = await repo.transactionsForMonth('2026-12');
    expect(
      december.where((t) => t.source == TransactionSource.statementImport),
      hasLength(3),
    );
    expect(december, hasLength(4));

    await db.close();
    docs.deleteSync(recursive: true);
  });
}
