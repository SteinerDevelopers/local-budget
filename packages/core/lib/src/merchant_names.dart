/// Merchant-name suggestion rules (pure, deterministic, DB-driven).
///
/// Separate from [PayeeSanity]: that gate judges OCR text in ISOLATION;
/// this file compares a scanned candidate against names the ledger ALREADY
/// knows, where a one-glyph divergence is far more likely a misread than a
/// brand-new business. Suggestions only ever prefill an editable field —
/// nothing here rewrites stored data or skips the review sheet.
library;

/// #44 — the OCR tail-duplication: a rasterized logo trail read the
/// merchant's final glyph twice, so `Walmart` scanned as `Walmartk` and
/// shipped a second, almost-the-same merchant row (tester report
/// 2026-11-06). When the ledger already holds the merchant under the
/// un-doubled spelling, return the stored name.
///
/// Deliberately narrower than fuzzy matching: the ONLY accepted edit is
/// `stored + stored's own last character`, so genuinely different names
/// (`Costco` vs `Costco Plus`, `Shell` vs `Shells Market`) can never be
/// merged, and a real new merchant is never hijacked.
String? correctTailDuplication(String scanned, List<String> known) {
  final s = scanned.trim().toLowerCase();
  for (final k in known) {
    final n = k.trim().toLowerCase();
    if (n.length < 3 || s.length != n.length + 1) continue;
    if (s == n + n[n.length - 1]) return k;
  }
  return null;
}
