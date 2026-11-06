# E12 · Document depth — frequencies, categories, layouts, batches, line items

Owner approval 2026-11-05: *"I approve moving forward with all 6 items"* — the six
candidates that E11 §8 left out of scope. This spec turns them into milestones
under the same binding rules as E11: pure-Dart parsing, review-first, zero new
network touch, zero new permission, on-device literally true.

**Prior:** `docs/design/e11-document-import.md` (router, statement + bill routes).
**Epic:** issue #41.

## 1. Frequency engine — quarterly & biweekly

`BillFrequency` (packages/budget/lib/src/rules.dart) is the single source of
truth; the drift column is a plain string, so new keys are additive.

- Add `biweekly('biweekly')` and `quarterly('quarterly')`.
- `nextDueAfter`:
  - **quarterly** — like monthly but advances in 3-month steps anchored on the
    rule's start month (`startEpochDay`); day-of-month keeps the clamp rule
    (a "31st" quarterly bill lands on month end in short months).
  - **biweekly** — every 14 days anchored on `startEpochDay` (the occurrence
    the user reviewed); `dayOfWeek`/`dayOfMonth` are ignored for this kind.
- Unknown-key fallback (`fromStorage → monthly`) keeps older app builds reading
  newer rows *conservatively* (they bill too often, never too rarely); noted in
  the changelog. No schema migration.
- Editor: frequency row becomes a scrollable chip set
  `Weekly · Biweekly · Monthly · Quarterly · Yearly`; the Bills tab cadence
  label ("Monthly · 5th") gains `Every 2 weeks · <anchor date>` and
  `Quarterly · <season-month> <day>`.
- Capture side: `BillFrequencyHint` stops degrading quarterly to monthly —
  the detector already recognizes quarterly prose (`_quarterlyRe`); a biweekly
  detector ("biweekly", "every 2 weeks", "each fortnight") is added. A hint
  only ever *prefills* the chip; review stays required.

## 2. Category inference per imported row

New pure-Dart `CategoryHints` in packages/core (no DB, no context): a
token→category function over a row's payee/description text against the app's
**built-in** category seeds, returning a suggestion + `FieldConfidence`.

- High only on unambiguous brand tokens (e.g. a fuel chain, a known streaming
  service); everything else ships medium or nothing. Never invents categories
  the user doesn't have — suggestions map to built-in ids; an unknown id falls
  back to empty.
- `buildPreview` (packages/data csv_import) attaches the hint to each
  `CsvPreviewRow`; the Preview's category cell **preselects** the suggestion and
  shows the amber "maybe" marker for medium confidence (truthfulness bar: amber
  = uncertain, never a silent pick).
- Inference is deterministic and unit-tested with redacted fixtures only.

## 3. Per-bank layout profiles

The statement parser already *derives* per-document parameters (decimal style,
amount side, date order). A profile persists that derived snapshot per issuer so
repeat statements parse identically without re-guessing.

- Keyed store: the existing `Settings` table, key `stmt.layout.<normalized
  issuer>`; value = compact JSON of the derived `StatementParseParams`
  (decimal comma/dot, amount-right/left, date order, debit/credit layout).
- Learning: when a statement import is **committed** (user-reviewed), the
  snapshot is stored — commits are the owner's confirmation the parse was right.
- Applying: parser consults the profile only when the document's issuer name
  matches a known key (issuer vocabulary shared with `BillDraft`); a mismatched
  document parses with fresh derivation exactly as today.
- Honest surfacing: the Preview footnote reads "used saved layout for <issuer>
  — reset". Reset deletes the key (Manage → Import defaults). No telemetry.

## 4. Multi-document batches

Batching applies to the **statement route** only; the bill route stays 1:1
review-first per E11 decision 5 (a bill batch would mean skimming multiple
amounts on one screen — rejected).

- Wizard state becomes a queue: `List<PendingDocument>` (photo/PDF pickers can
  return multiple images; more can be added before review).
- Each document parses independently and lands as its own Preview tab,
  labeled `<issuer or file n> · <rows> rows`; the dedupe ledger is shared
  across the whole batch (the same row appearing in two documents of one batch
  is flagged once, source-first tab wins).
- Commit is per-tab (a bad document never blocks a good one); the wizard shows
  which tabs are committed and only exits clean when every tab is committed or
  dismissed.
- Memory: page-render caps (E11 §2) apply per document, batch total capped at
  `kRenderedPageCap × min(4, docs)` so four scanned PDFs can't balloon RAM.

## 5. Line-item extraction (reserved `LineItems` table)

`LineItems` already exists in the drift schema (transactionId FK, position,
name, quantity, unitPriceMinor, currencyCode) with no writer. M5 gives it one.

- New pure-Dart `ItemLines.tryParse(lines)` in packages/data: scans the block
  between a transaction row and its following total/summary boundary for
  item-shaped rows — free-text name at the left, price at the right, **no date
  on the line** (a date makes it another transaction row), optional quantity as
  a leading integer × (e.g. `2 × 4.99`). Stops at TOTAL/SUBTOTAL/TAX summary
  words and at the next dated row.
- Wiring: a statement row whose document contained item lines stores them when
  the row is committed (same transaction, same currency; `position` preserves
  document order). Documents without a trustworthy item block store nothing —
  silence is the honest answer, the transaction itself is unchanged.
- Display: transaction detail gains an expandable "Items (n)" section
  (amounts right-aligned, total line reconciles to the transaction amount; if
  the items don't reconcile the section is hidden and nothing is stored).
- The gold corpus gains two itemized fixtures; precision bar: items are stored
  only when every parsed price sums to the row's amount (±currency exponent).

## 6. iOS VisionKit parity (E10 seam)

The capture stack reaches ML Kit through one platform channel
(`openDocument` + text extraction). Parity = a second implementation of the
same seam: an iOS `TextExtractor` backed by VisionKit `ImageAnalyzer`, plus the
photo-library/PDF document picker already scaffolded under `app/ios/`.

- This milestone lands the **design + interface** only: the Swift-side protocol
  sketch, channel contract, and a build-gated stub in `app/ios/` so E10 owns the
  implementation. This environment has no macOS toolchain; claiming an iOS
  build without one would fail the truthfulness bar. No Dart behavior changes.

## 7. Milestones (each lands green on its own)

- [ ] **M1** frequency engine: enum + `nextDueAfter` + hint mapping + editor
      chips + Bills-tab labels + tests (pure Dart + widget) + golden refresh.
- [ ] **M2** `CategoryHints` + Preview preselect/marker + tests.
- [ ] **M3** `StatementParseParams` snapshot + Settings persistence + issuer
      matching + reset UI + tests.
- [ ] **M4** wizard queue + per-tab Preview/commit + shared dedupe + caps +
      widget/e2e coverage.
- [ ] **M5** `ItemLines.tryParse` + commit-time write + detail section +
      reconciliation rule + corpus fixtures.
- [ ] **M6** iOS seam design note + channel contract + stub (no build claims).

## 8. Definition of done (all milestones)

- `flutter analyze` + package `dart analyze` zero; touched files
  `dart format`-clean; all CI lanes green (commit-lint, unit suites, goldens
  compare, e2e-android).
- No new network touch, no new permission; "on your device" stays literally
  true.
- Truthfulness: inferred categories are marked uncertain unless high-confidence;
  saved layouts disclose themselves and can be reset; line items only exist
  when they reconcile; no auto-commit anywhere.
