import 'money.dart';

/// How a transaction entered the ledger. The `transactions.source` column is
/// this discriminator (feasibility §5); analytics and settings features may
/// branch on it, behaviour never degrades because of it.
enum TransactionSource {
  manual('manual'),
  cameraScan('camera_scan'),
  screenshotImport('screenshot_import'),
  pdfImport('pdf_import'),
  statementImport('statement_import'),
  recurringTemplate('recurring_template');

  const TransactionSource(this.wireName);

  /// Stable DB wire name — never rename, values are stored.
  final String wireName;

  static TransactionSource fromWire(String name) =>
      values.firstWhere((s) => s.wireName == name,
          orElse: () => throw ArgumentError('unknown source: $name'));
}

/// Confidence metadata attached to every auto-extracted field. The review
/// sheet highlights low-confidence fields so the user's attention goes where
/// errors live (§4.5: the review sheet is the product's spine).
enum FieldConfidence { high, medium, low }

/// A receipt as understood *before* the user commits it (never auto-saved —
/// decision 5's UI consequence).
class ReceiptDraft {
  const ReceiptDraft({
    this.merchant,
    this.merchantConfidence = FieldConfidence.low,
    this.date,
    this.dateConfidence = FieldConfidence.low,
    this.dateIsAmbiguous = false,
    this.total,
    this.totalConfidence = FieldConfidence.low,
    this.rawLines = const [],
    this.usedLlm = false,
  });

  final String? merchant;
  final FieldConfidence merchantConfidence;

  final DateTime? date;
  final FieldConfidence dateConfidence;

  /// Day/month swap cannot be resolved from the text alone (e.g. `03/04/26`).
  final bool dateIsAmbiguous;

  final Money? total;
  final FieldConfidence totalConfidence;

  /// Original OCR lines, kept for the review sheet and future v2 line items
  /// (decision 2: the pipeline never throws this away even though v1 only
  /// stores the header).
  final List<String> rawLines;

  final bool usedLlm;

  bool get isComplete => merchant != null && date != null && total != null;
}

/// v2 — line-item extraction is reserved, not built (decision 2). The type
/// exists now so schema and serialization evolve without migration drama.
class LineItem {
  const LineItem({required this.name, required this.amount, this.quantity});

  final String name;
  final Money amount;
  final double? quantity;
}
