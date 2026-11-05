# E11 Design Spec — Document Import (bills & bank statements from image / PDF / photo)

**Status:** Design-first deliverable per decision 10; owner request 2026-11-04
("import Bills and Bank statements via image, PDF, or photo"). Binding:
implementation may not invent layout/behavior not described here; deviations
are spec edits first, code second.

E11 is deliberately *not* a new pipeline. E2 proved scan→review→save for one
receipt; E5 proved preview→dedupe→bulk-commit for statement files. E11 bolts a
router onto the two existing machines and adds the parsing they lack — the
statement *line* parser and the bill *rule* drafter. No new tab (E5's rule
survives), no new review chrome (E2's review sheet is reused verbatim for
bills), no new network touch (decision 8 unchanged: the OCR that feeds this is
the same on-device ML Kit text recogniser; nothing is uploaded).

Carried principles (E1/E2/E5, unchanged), restated for documents:

7. **One document in → at most one save target.** A *statement* is the single
   sanctioned exception E5 already made: one statement document → one preview
   → a checked bulk commit. Anything that is not a statement keeps E2's 1:1
   rule: one review, one save.
8. **Extraction proposes, the human disposes** (decision 5). Preview rows
   start unchecked-when-duplicate, bills prefill an editor that must be
   confirmed; no commit without a tap, and the copy never implies otherwise.
9. **Correctness surface stays pure Dart.** Line parsing, dedupe, date and
   money interpretation are unit-tested heuristics (packages/core +
   packages/data). The LLM tiers keep their E2 contract — fill-only, never
   overwriting a heuristic or a human edit — and are **never used to produce
   statement rows**: a hallucinated transaction is worse than a missing one.

---

## 1. Information architecture

```
Manage → Import statement (E5 screen, one new row):
├── CSV file          (E5, unchanged)
├── OFX file          (E5, unchanged)
└── Photo or PDF …    (E11) → on-device text → Router (classify)
        ├── bank statement   → StatementLines → CsvPreview → wizard Preview/Done
        ├── bill / invoice   → BillDraft → showBillEditor(prefill) → addRule
        └── receipt / other  → "use the scanner" pointer (no dead end, no 2nd receipt UI)
```

The router is `DocumentRouter` (packages/capture): given text lines it returns
`DocRoute.statement | DocRoute.bill | DocRoute.other`, computed from
`ReceiptHeuristics.classify` + a *line-density test* (≥ kStatementMinRows = 3
parsable transaction-looking lines) so a statement page whose keyword misses
still routes on structure, and a keyword-hit utility bill still routes on
signature. Precedence: **bill signature beats line-density** when a parseable
due-date + amount-due pair exists (a one-page card bill is dense but a bill);
statement wins otherwise. `other` is not an error: the sheet explains and
offers the two file formats (E5) or the capture FAB (receipts).

## 2. Getting text out of documents (capture package)

- PDF with a text layer ≥ `kTextLayerMinChars`: **all pages** now feed the
  parser. `PdfText` gains `List<List<String>> readTextLayerPages(Uint8List)`
  (lines grouped per page, page order — a flat `List<String>` cannot carry
  the grouping the plural implies). Dart's `implements` ignores bodies on
  interface members, so the delegating default is an
  `extension PdfTextPages on PdfText` that groups `readTextLayer`'s output at
  its stream-boundary markers (no adapter churn). `SimplePdfText.readTextLayer`
  already walks *every* content stream, so that grouping is its real
  multi-page walk. `readTextLayer` itself is untouched: single-page documents
  are byte-identical in behavior.
- Scanned PDF / image: existing `TextRenderer` → render pages (new
  `renderPages`, likewise an extension defaulting to `[renderPage1]`) →
  `TextExtractor.extractText` per page, concatenated in page order. Shared
  page budget `kRenderedPageCap = 10` (`pdf_text.dart`) — the ML Kit/pdfium
  adapter and the wizard enforce it so a 40-page PDF cannot hang the phone;
  truncation is disclosed in the Preview header ("first N pages"). An adapter
  that truly renders several pages declares `renderPages` on its concrete
  class (extension members never dispatch virtually).
- Tier-3 structuring runs **only** on the bill route (merchant/date/total
  fill-only, exactly as E2 §6). Never on the statement route (§ principle 9).

## 3. Statement route (data + wizard)

New pure-Dart module `packages/data/lib/src/statement_lines.dart`:

- `StatementLines.tryParse(List<String> lines, {required Currency currency, DateTime? now})`
  → `StatementParse({List<StatementRow> rows, int skippedLines})`. A line is a
  row iff, scanning right-to-left, it yields **amount + optional balance +
  date**, using only the existing strict helpers (`parseAmountCell`,
  `csvDateFormats`/`parseDateWithFormat`). Rules, conservative by construction:
  - the **amount** is the right-most currency-parsable token that is not a
    date and not a balance-looking continuation;
  - when ≥3 numeric tokens trail the description, the **right-most is treated
    as the running balance and dropped**, the next one is the amount (card and
    bank statements agree on this column order); a line where the two parse to
    equal values keeps one amount and no balance;
  - the **date** is the left-most parsable date within ±1 year of `now`;
    year-less formats (bank rows often omit the year) inherit the year from
    the previous row, rolling forward across December→January;
  - **no currency symbol needed on every row** (statements print it in the
    header); a bare `1.234,56` vs `1,234.56` decimal style is *inferred once
    per document* from token statistics and must be unambiguous, else the
    document is refused with a hint to use CSV;
  - income vs expense: a leading `-` or the debit/credit two-column layout
    (alternating blank cell → same width slot) decides; ambiguity marks the
    row amber and defaults to expense — the human flips it in review.
- `StatementRow{date, minor, isIncome, description, ambiguous}` maps 1:1 to
  `CsvPreviewRow` (externalId stays null — dedupe is the E5 date|amount|
  direction tuple via `CsvImport._dedupKey`, already the rule for FITID-less
  OFX rows). Commit rides `CsvImport.commit` unchanged; **source stays
  `TransactionSource.statementImport`** — same meaning as OFX/CSV rows; no new
  enum value, wireNames keep their stability promise.
- Preview UI is the E5 panel, reused verbatim (checkboxes, duplicate badges,
  account dropdown). New copy line on this route's Preview:
  *"Scanned rows are matched against what's already in the account."*

## 4. Bill route (core + bills sheet)

- `BillDraft` (packages/core, `heuristics.dart` sibling `bill_heuristics.dart`):
  `BillDraft.draft(List<String> lines, {required Currency currency, DateTime? now})`
  → `{payee?, amountDue?, dueDate?, frequency?, perField Confidence}`.
  - payee: `guessMerchant` under the utility/card anchor sets (already
    DocType-aware); amount: `guessTotal` (DocType anchors already prefer
    TOTAL/AMOUNT DUE over statement balance);
  - **dueDate is new**: nearest line containing a `DUE DATE`-family signature
    whose adjacent parsable date is in `now-7d … now+90d`; if only a
    statement-period end exists, that + a default 21-day float becomes the
    *suggestion*, marked low-confidence (amber, E2 §4 language);
  - frequency: monthly default; `WEEKLY`/`QUARTERLY`/`YEARLY`-family tokens
    near the amount override (quarterly maps to the nearest supported
    monthly/`monthly`-3-months note — the engine has no quarterly rule; the
    editor shows monthly with the next-due cursor on the parsed date);
  - Tier-3 fill-only merge applies here with a sibling JSON contract
    (`{"payee","dueDate","amountCents","frequency"}`) — additive to
    `llm_json.dart`, never touching the receipt prompt.
- Save path: `showBillEditor(prefill: BillPrefill(name: payee, amountMinor:
  amountDue))` with start/next-due seeded from `dueDate` (editor grows one
  optional prefill field `dueDate` — one-line change in `BillPrefill`),
  `notify` default ON (E3 behavior). Confirmed tap calls `repository.addRule`
  — the same persistence as manual bill creation; document capture mints
  nothing special. One bill per document (principle 7).
- Copy under the bill review header: *"We read this from your document —
  check it before saving."* (no auto-commit promise, decision 5).

## 5. UI wiring (app)

- `ImportWizardScreen`: `_isOfx` bool → `enum ImportFormat { csv, ofx, document }`.
  Source panel gains row `import-pick-document` — *"Photo or PDF — bill or
  bank statement"*. Tapping opens the E2 source sheet *without* the screenshot
  row (reuse `showCaptureSourceSheet`; choices limited to camera/photos/PDF —
  the picker machinery in `CaptureIntake` is reused, no new platform channel).
- While the document is being read: existing wizard frame shows the E2
  spinner state; failure states mirror E2 review-sheet copy ("couldn't read
  text — try CSV or OFX instead" for `other`/refusals).
- Router result `bill` pushes `showBillEditor` on top of the wizard's Source
  panel (not Done — a bill is not an N-row import); after save the wizard pops
  to Done with `n = 1` wording *"Bill saved."*
- Share/open-with keeps E2's meaning (receipt → review). Sharing a statement
  PDF lands in the same router with an explicit note: *"Looks like a statement
  — open it in Manage → Import?"* (sheet → wizard hand-off, one tap).

## 6. Privacy, copy-truthfulness, budget

- Still exactly three network touches system-wide (FX, own-cloud, unlock);
  this feature adds none. "On your device" claims here are literally true:
  ML Kit bundled model + Dart parsing.
- Golden frames: new Source panel (third row), statement Preview (same
  widget, new copy), bill editor with prefill badge states — regen via the
  CI `goldens:generate` lane, byte-changed PNGs only.
- e2e-android: one journey added — fake extractor feeds a canned statement's
  lines → Preview shows N rows, 1 duplicate → commit → ledger count +N.
- Benchmark: `tool/corpus_gen.dart` grows a statement script + a bill script;
  budgets: statement row precision ≥ 0.90, bill amount-due precision ≥ 0.85
  on the generated corpus (gold backend, CI-runnable headless).

## 7. Milestones (each lands green on its own)

1. **M1 — parsers (pure Dart).** `statement_lines.dart` + `BillDraft` +
   `guessDueDate`, unit tests with inline fixtures (E5 test style), benchmark
   scripts. No UI touched.
2. **M2 — router + multi-page text.** `DocumentRouter`, `readTextLayerPages`
   /`renderPages` extensions, statement→`CsvPreviewRow` bridge, capture/data
   tests.
3. **M3 — wizard + bill prefill wiring.** `ImportFormat` enum, source row,
   route hand-offs, `BillPrefill.dueDate`, share-sheet note; widget tests.
4. **M4 — gates & docs.** goldens regen, e2e journey, help article
   ("Import a bill or statement from a photo/PDF"), store/help copy sync,
   project-plan epic row + feasibility §4.1-9 amendment.

## 8. Out of scope (M3 backlog candidates)

Line-item extraction from statements/bills (the reserved `LineItems` table);
automatic category inference per row; saved per-bank *layout* profiles for
scanned statements (dedupe covers re-imports); multi-document batches;
quarterly/biweekly frequencies in the rule engine; iOS VisionKit parity (E10).
