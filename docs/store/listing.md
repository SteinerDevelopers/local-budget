# Store listing copy — Steiner's Private Budget (Android / Google Play)

_Draft v1 — 2026-11-03. Character limits counted on-device, not
approximated. `<…>` marks owner decisions to fill before publishing._

## Identity

- **Name:** Steiner Budget (13 chars) — full name *Steiner's Private Budget*
- **Developer:** Steiner Developers, L.L.C. (shown as store developer)
- **iOS subtitle (conditional E10):** "Private budgeting, offline" (26 chars)
- **Package:** `dev.steiner.local_budget` (frozen, #10)
- **Category:** Finance · **Tags:** budget, expense tracker, offline
- **Contact email:** `<OWNER-CONTACT — same as privacy policy>`
- **Privacy policy URL:** `<hosted copy of docs/legal/privacy-policy.md>`

## Short description (80 max)

> Budget by hand, keep every receipt — your data never leaves your phone.

(73 chars. Leads with the two things we are actually best at: honest
manual capture with proof attached, and literal local-only storage.)

## Full description (Play, 4000 max)

> Most budgeting apps want your bank login, your cloud, or your
> attention. Steiner Budget wants nothing. You type what you spent —
> or photograph the receipt and tap the numbers it found — and it all
> stays on your phone. No account. No analytics. No ads. Uninstalling
> removes every byte.
>
> **Capture that respects your time**
> · Quick-add a coffee in four taps, keypad first like a calculator
> · Photograph or scan a receipt: the app highlights the words it
>   actually read, and you approve. No silent guesses.
> · PDFs, screenshots, shared images — the same review screen, always
>   offline. Attachments live with the entry, so “what was this?” has
>   a picture as an answer.
> · Import a bank statement (CSV or OFX) when you want to catch up on
>   a month. Re-importing the same file never doubles your ledger.
> · No file, just paper? Photograph a bill or a statement — Import
>   reads it into the same reviewed preview, or drafts the bill
>   reminder with the amounts and date for you to approve.
>
> **A month you can actually read**
> · Spent, income, and per-category limits against real spending
> · Budget vs actual, trends, and month-by-month reports — on-device
> · Multi-currency with a rate for every entry, so a holiday doesn't
>   warp your totals
> · Bills and savings goals that roll into the month view
>
> **Built to be left alone**
> · Every screen works on a plane. The only network calls are ones you
>   start: optional currency rates and your own encrypted backups.
> · Pro is a one-time unlock, not a subscription: detailed insights,
>   PDF reports, home-screen widgets, encrypted backup to your own
>   cloud, and cloud sync of your ledger to a WebDAV server you run.
> · **Paid only ever adds.** Nothing free becomes paid — the free app
>   budgets a whole household forever. Buying Pro can't move, hide or
>   gate anything that was already there.
>
> One tap on “?” opens offline Help with an article for every screen —
> it even searches without internet.
>
> Steiner Budget is made by one person who answers email. Feature
> requests shape it more than dashboards do, because there are no
> dashboards.

(≈1 900 chars — leaves headroom for screenshots-driven edits.)

## Data safety form, as filled

- Collects: **nothing.** (Rate lookups and your-own-storage backup are
  user-initiated device functions; nothing reaches the developer.)
- Shared: nothing. Encrypted: n/a (nothing collected).
- Delete flow: uninstalling is the deletion; say so in the form's
  free text.
- Family policy: not children's app; utility.

## What Pro adds (store listing graphic, one screen)

| | Free | Pro (one-time) |
|---|---|---|
| Manual + receipt capture, attachments | ✓ | ✓ |
| Statements import, budgets, bills, goals | ✓ | ✓ |
| Month/Year reports, export | ✓ | ✓ |
| Detailed insights & analytics | — | ✓ |
| PDF report export | — | ✓ |
| Home-screen widgets | — | ✓ |
| Encrypted backup to your own cloud | — | ✓ |
| WebDAV sync (your server) | — | ✓ |

Caption: “One purchase, yours forever. Nothing free ever moves behind
the paywall.”

## Screenshots checklist (owner — needs a real device/emulator)

Eight shots, 9:16, in this order (tells the story top-to-bottom):
1. Month screen with a filled balance strip (populate with a demo
   month, delete first — see below)
2. Capture review sheet with highlighted fields (proves OCR honesty)
3. A transaction detail with an attached receipt photo
4. Budgets sheet, one category near its limit (full green bar + honest number;
   the design has no amber state — green until red, §2.1)
5. Reports → Budget vs actual
6. Statement import preview
7. Help screen with a search typed in
8. Settings/About showing the privacy promise line

**Before capturing:** wipe demo data (`adb shell pm clear
dev.steiner.local_budget`) and re-enter a tidy month so nothing real
or e2e-junk is in frame; dark mode `<pick one and stay consistent>`.

## Feature graphic + icon

- **Icon: FINAL** — Vault-house geometry + fat `$` coin (row-2 winner,
  device-verified 260/420 dpi). Production assets:
  `app/android/app/src/{main,pro}/res` (adaptive layers all densities);
  decision trail in `docs/store/icon.md`.
- **Feature graphic: drafted, pending owner approval** —
  `docs/store/feature-graphic-free.png` / `-pro.png` (1024×500 PNG,
  ~40 KB, one amber on Pro, short description repeated at legible
  size per spec). Generator: `docs/store/feature-graphic/make-feature.js`
  (sharp + SVG, FONTCONFIG_FILE=`icon-candidates6/fonts.conf`).

## Release notes template (each Play rollout)

> **What changed**
> · <user-visible change in plain words>
>
> **Fixes** · <one line each>
>
> Still offline, still no accounts, still yours.
