/// Merchant-name suggestion rules (pure, deterministic, DB-driven).
///
/// Separate from [PayeeSanity]: that gate judges OCR text in ISOLATION;
/// this file compares a scanned candidate against names the ledger ALREADY
/// knows, where a one-glyph divergence is far more likely a misread than a
/// brand-new business. Suggestions only ever prefill an editable field —
/// nothing here rewrites stored data or skips the review sheet.
library;

/// #44 — the OCR tail appendage: a rasterized logo trail lent the
/// merchant an extra final character, so `Walmart` scanned as `Walmartk`
/// and shipped a second, almost-the-same merchant row (tester report
/// 2026-11-06). When the ledger already holds the merchant under the
/// clean spelling, return the stored name.
///
/// The accepted edit is narrow — [scanned] must equal a stored name plus
/// exactly ONE trailing character — so multi-word or clearly different
/// names (`Costco` vs `Costco Plus`) can never merge. The honest trade
/// (`Target` in the ledger swallows a scanned `Targets`) is deliberate:
/// the review sheet keeps the field editable, while a silently-created
/// near-duplicate merchant row costs the user forever.
String? correctTailDuplication(String scanned, List<String> known) {
  final s = scanned.trim().toLowerCase();
  for (final k in known) {
    final n = k.trim().toLowerCase();
    if (n.length < 3 || s.length != n.length + 1) continue;
    if (s.startsWith(n)) return k;
  }
  return null;
}
