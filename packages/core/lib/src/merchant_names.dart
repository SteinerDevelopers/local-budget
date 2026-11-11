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
