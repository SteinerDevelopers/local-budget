import 'package:core/core.dart';

/// Where a captured document's text goes next (e11 §1): the statement
/// wizard, the bill editor, or the "use the scanner / CSV instead" pointer.
enum DocRoute { statement, bill, other }

/// Routes extracted document text to one of E11's two existing machines —
/// never a third pipeline (e11 §1). Pure Dart: keyword signatures from
/// [ReceiptHeuristics.classify] plus a structure test (transaction-looking
/// lines) so a statement whose keywords missed still routes on layout.
///
/// Precedence (spec): a parseable due-date + amount pair is a *bill
/// signature* and beats line density — a one-page card bill is dense yet
/// still a bill. Otherwise density wins, then keywords.
abstract final class DocumentRouter {
  /// Transaction-looking lines (date and money on one line) needed before
  /// the document routes to the statement wizard on structure alone.
  static const int kStatementMinRows = 3;

  static DocRoute route(
    List<String> lines, {
    required Currency currency,
    DateTime? now,
  }) {
    if (_billSignature(lines, currency: currency, now: now)) {
      return DocRoute.bill;
    }
    var rows = 0;
    for (final l in lines) {
      if (_dateish.hasMatch(l) && _moneyish.hasMatch(l)) rows++;
    }
    if (rows >= kStatementMinRows) return DocRoute.statement;
    return switch (ReceiptHeuristics(currency: currency, now: now).classify(
      lines,
    )) {
      // A keyword-hit bill with an unparseable due/amount pair still gets
      // the bill editor (fields can be typed); slips and receipts get the
      // scanner pointer — E2's review is the only receipt UI (principle 7).
      DocType.utilityBill => DocRoute.bill,
      DocType.cardStatement || DocType.receipt => DocRoute.other,
    };
  }

  /// "A parseable due-date + amount-due pair exists" (e11 §1) — the same
  /// helpers the bill drafter uses, so router and drafter never disagree.
  static bool _billSignature(
    List<String> lines, {
    required Currency currency,
    DateTime? now,
  }) =>
      BillDraft.guessDueDate(lines, now: now) != null &&
      ReceiptHeuristics(currency: currency, now: now).guessTotal(lines) != null;

  /// Date-looking token: slash/dash pair, dotted date *with* year, or ISO.
  /// A bare `N.NN` is deliberately NOT date-looking — that is a decimal
  /// amount (`5.75`), and European statement dates always carry the year
  /// (`05.12.2026`). Any position on the line.
  static final RegExp _dateish = RegExp(
    r'\d{1,2}[/-]\d{1,2}|\d{1,2}\.\d{1,2}\.\d{2,4}|\d{4}-\d{1,2}-\d{1,2}',
  );

  /// Money-looking token: currency-ish with a decimal fraction or thousands
  /// groups. The lookarounds stop a date (`05.12.2026`) from passing as
  /// money; a bare integer never counts (statement amounts do carry cents
  /// or separators; REF numbers must not inflate density).
  static final RegExp _moneyish = RegExp(
    r'(?<![\d.,/-])[$€£¥]?\s?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?(?![\d.,/-])'
    r'|(?<![\d.,/-])[$€£¥]?\s?\d+[.,]\d{2}(?![\d.,/-])',
  );
}
