# E13 — Payee hardening (epic #42)

Owner-approved 2026-11-05 after the E12 PASS: three items, same binding rules —
pure-Dart, honest-empty over confident-wrong, no new network, no new permission.
CI lanes are the sole gate; the `ollamatest` advisor (routed per owner
instruction) informs tests/fixtures/review but never decides anything.

## 1. Where payees come from today (facts, not vibes)

One seam: `ReceiptHeuristics.guessMerchant(lines)` (`packages/core/lib/src/
heuristics.dart`) feeds both the receipt route (`merchant:`) and the bill route
(`BillDraft.fromLines` → `payee`, where remit-block, sheet-title rejection,
corroboration (`_providerCorroborated` / `_firstCorroboratedName`) and the
card-statement issuer rule already layer on top).

Guards today: length 2–40, ≥2 letters, **reject anything starting with a
digit**, address/legal tail, URL chrome, labelled-field vocabulary, SAMPLE
watermarks. A first-line survivor ships `high`; a later one `medium`.

## 2. The two shipped defects

**D1 — raster junk sails through.** `BOUI FVAFD` (photographed-screen OCR,
device session 2026-11-05) passes every guard: letters, no digit start, no
black vocabulary. Line 1 ⇒ `high` confidence, and corroboration only *replaces*
when the paper offers a corroborated alternative — a lone junk line on a raster
photo ships untouched.

**D2 — digit-leading merchants die.** The `^\d` reject was aimed at dates,
phones and bare numerals; it also kills `99¢ ONLY`, `24 HOUR MARKET`,
`5 GUYS BURGER`, `1-800-FLOWERS`. The merchant simply goes missing.

## 3. M1 — junk-vocabulary gate (silence, never a guess)

New pure function `PayeeSanity.junkName(String line) -> bool` consulted inside
`guessMerchant` before accepting any candidate, and inside the corroboration
replacement path so an alternative is judged by the same bar.

A line is junk when any letter-token of length ≥ 3 is *unpronounceable*:
- all-consonant and length ≥ 4 (`FVAFD`; but `XYZ`, `CNN`, `TGI`, `TV` at 1–3
  letters are letter-brand territory and pass), or
- the token's leading consonant cluster is not an attested English onset
  (whitelist: single consonants + `bl br ch cl cr dr fl fr gl gr kl kn kr ph
  pl pr qu sc sh sk sl sm sn sp spr sq st sw thr th th tr tw wh sch scr spl
  squ`) **and** no vowel appears within the token's first two characters —
  this catches `FVAFD` (onset `FV`, first vowel at index 2) while `TGI` (≤3
  letters), `XYZ` (≤3), `BOUI` (onset `B`) pass, or
- the token has fewer than three distinct letters (`AAAAA`, `IIIII` — raster
  echo runs; advisor case, adopted after the vowel rule alone let it through).

Seeded brand whitelist bypasses the gate entirely (deterministic, grows only
from real bounces): `AMZN MKTP` (Amazon's own OCR-normal name is all-consonant
but real — advisor-flagged, owner-visible tradeoff accepted).

Corroboration outranks the gate exactly once: a junk-shaped name that appears
**twice or more** in the lines is kept at `medium` — some billers really do
print unpronounceable marks; the reviewer still sees it. A single junk hit
falls through to `_firstCorroboratedName`; with nothing better the payee stays
**null** (honest-empty). Confidence semantics unchanged otherwise.

Guard gap the corpus also closes (advisor #22): a letters-leading total line
(`TOTAL: $45.99`) must not mint a merchant — any line whose first word is
`TOTAL|SUBTOTAL|BALANCE|AMOUNT` **and** contains a numeral is rejected, while
`TOTAL WINE & SPIRITS` (no numeral) stays a keeper.

The gate may only ever *widen silence*: it can drop a junk payee to null or to
a corroborated real name, and never invent or rewrite text.

## 4. M2 — digit-leading keepers

Replace the blanket `^\d` reject with a merchant-shape test. Order matters
(advisor case `24/7 MARKET`, adopted): merchant vocabulary or corroboration
**outranks** the date/phone/noise shapes. A digit-leading line survives when
1. it contains at least one letter-token of length ≥ 3, **and**
2. it is corroborated (≥2 occurrences) **or** carries merchant vocabulary
   (`MARKET|STORE|SHOP|CAFE|CAFE|DELI|DINER|PIZZA|FOODS|FLOWERS|BURGER|BAR|
   SALON|PHARMACY|STATION|GARAGE|LAUNDROMAT|MOTEL|WORKS|SUPPLY|ONLY|CO|INC|LLC`
   — `ONLY` seeded from the owner's `99¢ ONLY` receipt header, which prints
   once);

unless it is hard noise: phone shapes (`\d{3}[- ]\d{4}`, 7+ consecutive
digits — note `1-800-FLOWERS` has only three in a row and survives), discount
prose (`^\d+(\s*(OFF|%|PERCENT)|\sFOR\s)`), or a date shape **with no merchant
word anywhere on the line** (`03/15 DUE` dies, `24/7 MARKET` lives).

Downstream isolation: the survivor lands only in `merchant`/`payee`;
`guessTotal` never anchors on it (no `TOTAL…` vocabulary there) — pinned by
fixture, e.g. `99¢ ONLY` + `TOTAL 12.50` ⇒ total 12.50, payee `99¢ ONLY`.
Survivors enter at `medium` unless corroborated twice on line 1 (kept `high`
only when the existing first-line rule also fires).

## 5. M3 — consolidated bounce corpus

Table-driven `payee_corpus_test.dart` (packages/core/test): rows of
`{lines, expectedPayee, expectedConfidence}` covering every collected real
bounce plus the two new classes — Citi card statement (issuer trim), radiology
stub (`MRA` logo + heading ≠ payee), pen-brand desk clutter, browser-chrome
photo, CFPB labelled-field lines (`NAME|ADDRESS|ACCOUNT|DATE|PAYMENT`),
ENERGEL receipt, `BOUI FVAFD` raster junk (single ⇒ null; doubled ⇒ medium),
`99¢ ONLY` / `24 HOUR MARKET` (keepers), `1234 5678 9012` / `10 OFF TOTAL` /
`03/15 DUE` (rejects), odd-but-real keepers (`TGI FRIDAYS`, `H&R BLOCK`,
`XYZ STORE`, `TV DINER`).

Fixture sources: the code comments already cite each historical bounce;
synthetic candidates were advisor-generated (ollamatest, 2026-11-05) and each
one was **run against the real parser before saving** — anything ambiguous
was cut. The corpus is the regression bar: keepers never drop, bounces never
pass.

## 6. Definition of done

`dart analyze` / `flutter analyze` zero; touched files `dart format`-clean
**before** commit (the E12 formatter-lane lesson); all CI lanes green including
goldens compare (expect zero golden changes — payee text is not in any golden
scene; if one moves, regenerate on the new pipeline and commit refs); no new
permission, no network. Advisory policy: every ollamatest finding checked
against code before adoption; nothing user-facing ships on advisor word alone.
