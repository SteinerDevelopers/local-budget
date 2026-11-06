// E12 §4 — the multi-document batch journey: two photographed statements
// in one session arrive as review tabs with a shared dedupe ledger (the same
// row in both documents is flagged once), each tab commits on its own, and
// the wizard only calls it "done" when every document is committed. Only
// OCR/picker are faked; routing, parsing, dedupe, commit and the ledger are
// the shipped path.
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:capture/capture.dart' show TextExtractor;
import 'package:core/core.dart' show TransactionSource;
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

/// Hands out one document's OCR lines per call — the batch's second photo
/// reads the second statement, exactly like a second tap of the picker.
class _QueueExtractor implements TextExtractor {
  _QueueExtractor(this.documents);
  final List<List<String>> documents;
  int _next = 0;

  @override
  Future<List<String>> extractText(Uint8List image) async => documents[_next++];
}

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  const docA = [
    'FIRST NATIONAL TEST BANK',
    'DATE DESCRIPTION AMOUNT BALANCE',
    '12/10/2026 ALPHA MART 10.00 900.00',
    '12/11/2026 BRIO CAFE 4.50 895.50',
    '12/12/2026 SALARY PLUS +900.00 1,795.50',
  ];
  const docB = [
    'FIRST NATIONAL TEST BANK',
    'DATE DESCRIPTION AMOUNT BALANCE',
    '12/11/2026 BRIO CAFE 4.50 891.00', // same tuple as doc A's cafe row
    '12/13/2026 DELTA FUEL 33.00 858.00',
    '12/14/2026 QUICK LOTTO 6.00 852.00',
  ];

  testWidgets('two statements batch: tabs, shared dedupe, per-tab commit', (
    tester,
  ) async {
    final docs = Directory.systemTemp.createTempSync('lzb_batch');
    final db = AppDatabase.openFile('${docs.path}/localbudget.sqlite');
    final repo = LedgerRepository(db);
    await repo.ensureDefaults();

    await tester.pumpWidget(
      LocalBudgetApp(
        repository: repo,
        db: db,
        docsDir: docs,
        capture: CaptureServices(
          intake: _DocIntake(),
          extractor: _QueueExtractor(const [docA, docB]),
        ),
      ),
    );
    await tester.pumpAndSettle();

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

    // Document A → one tab (no strip for a batch of one), three rows.
    await tester.tap(find.byKey(const Key('import-pick-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-row-2')), findsOneWidget);
    expect(find.byKey(const Key('import-batch-tabs')), findsNothing);

    // The batch grows: Add another → second statement lands as tab 2.
    await tester.tap(find.byKey(const Key('import-add-another')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-batch-tabs')), findsOneWidget);
    expect(find.textContaining('2. Document 2'), findsOneWidget);

    // Inside one batch the same row counts once: the cafe row from doc A
    // arrives already flagged in doc B — the earlier tab keeps it.
    expect(find.textContaining('already imported'), findsOneWidget);
    expect(find.byKey(const Key('import-row-2')), findsOneWidget); // B: 3 rows

    // Commit tab 2 first (the new fuel row only); tab 1 stays open.
    await tester.tap(find.byKey(const Key('import-commit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-tab-committed')), findsOneWidget);
    expect(find.textContaining('still open'), findsOneWidget);

    // Back to tab 1, commit its three rows; only now is the batch done.
    await tester.tap(find.byKey(const Key('import-batch-tab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-commit')));
    await tester.pumpAndSettle();
    expect(find.text('Imported 5 transactions'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-close')));
    await tester.pumpAndSettle();
    final december = await repo.transactionsForMonth('2026-12');
    expect(
      december.where((t) => t.source == TransactionSource.statementImport),
      hasLength(5),
    );

    await db.close();
    docs.deleteSync(recursive: true);
  });
}
