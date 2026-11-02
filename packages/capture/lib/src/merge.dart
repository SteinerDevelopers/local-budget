import 'package:core/core.dart';

/// The fields the review sheet tracks individually.
enum DraftField { merchant, date, total }

/// True when a field is missing or was extracted at low confidence — the only
/// fields Tier 3 may touch.
bool needsFill(Object? value, FieldConfidence confidence) =>
    value == null || confidence == FieldConfidence.low;

/// Tier-3 merge rule (e2-capture.md §3, binding):
///
/// * fill only fields that are null or `low` in [base];
/// * never overwrite `medium`/`high` fields, even if the structurer disagrees;
/// * never touch fields in [userEdited], however they came to be there;
/// * [llm] null → [base] returned untouched.
///
/// `usedLlm` is set when at least one field was actually filled — it is
/// metadata for debugging only, the UI never surfaces it (decision 10).
ReceiptDraft mergeDraft(
  ReceiptDraft base,
  ReceiptDraft? llm, {
  Set<DraftField> userEdited = const {},
}) {
  if (llm == null) return base;

  var merchant = base.merchant;
  var merchantConfidence = base.merchantConfidence;
  var date = base.date;
  var dateConfidence = base.dateConfidence;
  var dateIsAmbiguous = base.dateIsAmbiguous;
  var total = base.total;
  var totalConfidence = base.totalConfidence;
  var filled = false;

  if (!userEdited.contains(DraftField.merchant) &&
      llm.merchant != null &&
      needsFill(merchant, merchantConfidence)) {
    merchant = llm.merchant;
    merchantConfidence = llm.merchantConfidence;
    filled = true;
  }
  if (!userEdited.contains(DraftField.date) &&
      llm.date != null &&
      needsFill(date, dateConfidence)) {
    date = llm.date;
    dateConfidence = llm.dateConfidence;
    // The structurer either resolves the ambiguity or reproduces it; it
    // cannot leave the sheet claiming less doubt than the heuristic had.
    dateIsAmbiguous = llm.dateIsAmbiguous;
    filled = true;
  }
  if (!userEdited.contains(DraftField.total) &&
      llm.total != null &&
      needsFill(total, totalConfidence)) {
    total = llm.total;
    totalConfidence = llm.totalConfidence;
    filled = true;
  }

  if (!filled) return base;
  return ReceiptDraft(
    merchant: merchant,
    merchantConfidence: merchantConfidence,
    date: date,
    dateConfidence: dateConfidence,
    dateIsAmbiguous: dateIsAmbiguous,
    total: total,
    totalConfidence: totalConfidence,
    rawLines: base.rawLines,
    usedLlm: true,
  );
}
