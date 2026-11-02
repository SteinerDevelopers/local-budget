# E2 Design Spec — Capture Pipeline (scan → review → save)

**Status:** Design-first deliverable per decision 10. Binding: implementation may
not invent layout/behavior not described here; deviations are spec edits first,
code second. Scope is getting a bill/receipt **into** the ledger via camera,
screenshot or PDF — the ledger frame from E1 does not move; capture is a guest
that enters through the FAB column and the review sheet.

Carried principles (from E1, unchanged): one-handed · optional fields never
block save · money is the hero · quiet chrome · offline truth. E2 adds one:

6. **Never auto-commit** (decision 5's UI consequence): extraction *proposes*,
   the human *disposes*. A capture can pre-fill, highlight, and suggest — it
   cannot save, and the copy never implies otherwise. One document in →
   exactly one review → at most one transaction.

---

## 1. Information architecture

```
Ledger (home)
├── FAB (primary)   → QuickAdd sheet            (E1, unchanged)
└── FAB (secondary, above) → Capture source sheet (E2, modal)
        ├── Camera        → platform scanner → Review
        ├── Photos        → photo picker      → Review
        ├── PDF file      → SAF document picker → Review
        └── Last screenshot (Android convenience) → Review

External intakes (no source sheet — file is already chosen):
  share-sheet "Add to Budget" / open-with  → Review (app launches on it)
```

The secondary FAB is `Icons.document_scanner_outlined`, placed 12 dp above the
primary per Material stacked-FAB spacing; it appears on the Ledger only.
Deep-link entry (share/open-with) opens the app on the Review sheet above the
Ledger — the user can always back out to an untouched ledger.

## 2. Screens

### 2.1 Capture source sheet
Bottom sheet, same 48 %-height frame rules as QuickAdd; four full-width list
rows (icon + label, 56 dp): **Camera**, **Photos**, **PDF file**, and on
Android **Recent screenshot** (opens photo picker pre-scoped to Screenshots;
if permission-less picking fails, the row hides itself — never a dead end).
One row per tap; the sheet closes as the picker/scanner opens.
Copy line under the header: *"One receipt at a time — you review before it's
saved."* (decision 5 made audible).

### 2.2 Scanner — platform UI, zero custom chrome
Android: ML Kit Document Scanner (edge detection, perspective crop, multi-page
→ page 1 is the document's face). iOS: VisionKit `VNDocumentCameraViewController`.
We render nothing: users already know these scanners. Result = image bytes
(hand-off contract §3). If the platform scanner is unavailable (old device,
user cancelled), fall back to plain camera capture — still one image out.

### 2.3 Review sheet — the product's spine (§4.5)
Bottom sheet at 92 % height (this screen is *used*, not glanced at). Top-down:

1. **Source strip** (88 dp): thumbnail of the image / PDF page 1 + badge
   (`Scan` / `Screenshot` / `PDF`) + processing state. While extraction runs
   the strip shows an inline indeterminate bar (local work, §offline truth);
   fields below are revealed as they land. Tap thumbnail → fullscreen viewer
   (pinch-zoom is M2; tap-to-dismiss now).
2. **Amount** — same `AmountPad` as QuickAdd (reused widget, same tests),
   pre-filled from extraction. This is the one gate: Save enables iff
   amount > 0 **and** category selected (identical rule to QuickAdd).
3. **Date** — the QuickAdd date strip (Today / Yesterday / Calendar…),
   pre-filled from extraction; an ambiguous extraction (`03/04/26`) shows the
   field highlighted amber with helper *"Day and month are unclear — check."*
4. **Merchant** — `TextField`, pre-filled when confident; optional, never
   gates save. Placeholder *"Store name"*.
5. **Category** — the QuickAdd chip row (same warm-state rules): last used
   category preselected on repeat captures.
6. **Income/Expense** — SegmentedButton, Expense default; receipts are
   overwhelmingly expenses.
7. Save row: filled **Save** + text button **Discard**.

**Uncertainty highlighting (the mechanism):** every pre-filled field carries
a `FieldConfidence` from the draft (§3). `low` → amber 1.5 dp outline + one
helper line naming the fix ("Check amount", "Check date"). `medium` → nothing
visual (never cry wolf). The highlight clears the moment the user edits the
field. If total extraction failed entirely, the pad sits empty and a helper
under the thumbnail reads *"No total found — type it in."*

TalkBack (decision 10 bar): low-confidence fields append "— needs checking"
to their announcements; the source strip announces badge + progress.

**Save** → transaction with `source = camera_scan | screenshot_import |
pdf_import`, `imageRef` = attachment path (§4), merchant name persisted to
the `merchants` table (dedupe by name, case-insensitive). Then the same
Undo snackbar as E1 deletes *and* unlinks the attachment file.

### 2.4 Detail sheet (E1) — one addition
Rows with `imageRef` gain a thumbnail chip in the header; tap → fullscreen
viewer with **Delete image** as the only action (keeps E3 scope out).

## 3. Extraction pipeline contracts

Pure logic lives in `packages/capture` (new, Dart-only, no Flutter, no
plugins — CI-testable exactly like `core`/`data`). Platform adapters live in
the app behind these interfaces:

```
TextExtractor.extractText(Uint8List image) -> List<String> lines   // Tier 1
PdfText.readTextLayer(ByteFile pdf) -> List<String>                // §2.5 case A
ReceiptParser.parse(lines, {locale, baseCurrency}) -> ReceiptDraft // Tier 2
LlmStructurer.isAvailable() -> bool
LlmStructurer.structure(image, lines) -> ReceiptDraft?             // Tier 3
```

Pipeline (async, runs while the Review sheet is already open):
Tier 1 (or PDF text layer) → Tier 2 always → **Tier 3 only if**
`isAvailable()` **and** the draft has a null or low field. Merge rule,
binding: Tier 3 may only fill fields that are null or `low`; it never
overwrites `medium/high` values and never touches a field the user edited.
`usedLlm` is metadata only — zero UI promises about AI.

**Tier 2 heuristics (deterministic, 100 % unit-tested):**
- **Merchant** = first line in the top 5 that contains letters, length ≥ 2,
  and isn't all digits/phone/punctuation. `high` when it is the first line,
  `medium` deeper in the block.
- **Date** = last date token in the top 8 lines. Accepted shapes: ISO
  `YYYY-MM-DD`, `D/M/Y` vs `M/D/Y` (locale pref `en-US` default; ambiguous
  when day ≤ 12 and both orders valid → `dateIsAmbiguous`, shown highlighted),
  `MMM D, YYYY`. Dates > 1 day in the future are rejected (receipts don't
  pre-date), dates > 2 years back are accepted silently.
- **Total** = amount on the *last* line matching the anchor list, priority
  `NET TOTAL > GRAND TOTAL > TOTAL DUE > AMOUNT DUE > TOTAL > AMOUNT`;
  `SUBTOTAL`, `TAX`, `CHANGE`, `BALANCE` are anti-anchors — never the total.
  Amount = `Money.tryParse` of the largest numeric token on that line
  (already total-safe, #21). Currency = explicit symbol/code on the anchor
  line, else the device base currency.
- **Failures are states, not errors**: no lines (blurry scan) → empty draft +
  helper *"Couldn't read this — retype or try the image again."* Nothing ever
  crashes the review; Save only needs amount + category anyway.

**PDF (§2.5):** try text layer; < 20 chars on page 1 ⇒ treat as scanned →
render page 1 (pdfium adapter) → Tier 1 OCR. Multi-page = one document,
page 1 only (M1); statement splitting is v2 (decision 2/feasibility §2.5).

Perf target: picker-close → all fields filled ≤ 3 s on mid-range (§4.2);
the sheet itself opens in < 300 ms regardless of pipeline state.

## 4. Attachments & files (§2.6)

`AttachmentStore` (in `packages/data`, takes a directory — no plugins):
`saveOriginal(bytes, ext) -> relative path` under `attachments/`
(sha-free, ULID-style name `yyyymmddhhmmss-<src>.<ext>`), `delete(rel)`,
`resolve(rel) -> absolute File`. Originals stay full-resolution; thumbnails
are an M2 optimization (the review thumbnail renders from a downscaled
in-memory decode). `imageRef` already exists in schema v1 — **no new
migration**. Deleting the transaction deletes the file (E1 `deleteEntry`
callers go through an app-layer hook that unlinks after the DB commit;
Undo re-saves nothing — attachment is gone with the row, matching E1 Undo
semantics which re-insert a *new* row).

## 5. Android intake plumbing (M1 scope)

- `image_picker` for Photos + plain-camera fallback; photo picker (no
  permission prompt) via Android system picker.
- ML Kit Document Scanner + text recognition via their Flutter plugins
  (bundled model; no Play Services download dialog).
- PDF picking through SAF `ACTION_OPEN_DOCUMENT` (`image/*`, `application/pdf`).
- Share/open-with: `ACTION_SEND` (+ `SEND_MULTIPLE`) intent filter for
  `image/png|jpeg`, `application/pdf`; **multiple files: import the first,
  snackbar the rest** — decision 5 outranks cleverness; a queue is a
  fast-follow (§7).
- iOS targets compile and run the same Dart flow (VisionKit/Vision adapters
  stubbed behind the same interfaces where the plugin layer already covers
  them); heavy iOS validation stays deferred (decision 11) — but no code
  lands that is Android-only *by construction*.

## 6. Tokens & motion — no new tokens

Sheets, type, spacing, icons: E1's set verbatim. New colors: zero (amber =
existing `warning` token). Motion: extraction fills use the 150 ms fade E1
uses for value changes; no shimmer, no skeleton theatre.

## 7. Golden-test surface

Review sheet (populated high-confidence draft), review sheet (mixed
low-confidence: amber outlines + helpers), capture source sheet, ledger with
secondary FAB. Fake `TextExtractor` makes all four hermetic in `flutter test`.

## 8. Deliberately *not* in E2

Line items (decision 2, v2) · multi-page statement splitting (§2.5, v2) ·
scan queue / multi-share queue · thumbnail grid gallery (E3) · pinch-zoom
viewer (M2) · iOS validation & share-extension polish (decision 11 trigger) ·
Gemini Nano on non-flagships (Tier 3 is flagship-only by platform, by design)
· **any auto-commit path, anywhere, ever** (decision 5).
