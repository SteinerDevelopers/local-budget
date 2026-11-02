# E1 Design Spec — Manual Ledger Core

**Status:** Design-first deliverable per decision 10. Binding: implementation may
not invent layout/color/behavior not described here; deviations are spec edits
first, code second. Scope is the *manual* ledger only — receipts, budgets,
imports land later and must fit this frame without moving it.

Design principles (carried from the feasibility doc):
1. **One-handed** — everything reachable in the bottom two-thirds; primary
   actions right thumb, navigation left thumb.
2. **Two taps to a logged transaction** — open app → FAB → amount + category,
   done. Optional fields never block the save.
3. **Money is the hero** — tabular figures, generous size, never truncated.
4. **Quiet chrome** — no cards-in-cards, no shadows on flat lists, color only
   for meaning.
5. **Offline truth** — every screen works with the radio off; nothing ever
   implies sync (no spinners waiting on anything).

---

## 1. Information architecture

```
BottomNavigationView (2 destinations, fixed)
├── Ledger        (home — the month's transactions)
└── Manage        (categories + base currency + about)
FAB on Ledger → QuickAdd sheet (modal, not a destination)
Transaction tap → Detail sheet (edit/delete live there)
```

No drawers, no tabs-within-tabs, no nav beyond one stack hop. Settings live
inside *Manage* until there is enough of them to graduate (M2+).

## 2. Screens

### 2.1 Ledger (home)

Top → bottom:

| Zone | Content | Spec |
|---|---|---|
| Month switcher | `November 2026` + chevrons ‹ › | 22 pt label, centered between 48 dp chevron hit targets; horizontal drag on the header also pages months; no date picker from here |
| Balance strip | 3 stats: **Income**, **Expenses**, net | single row, 56 dp tall; labels 12 pt `onSurfaceVariant` caps; values 16 pt tabular; net uses primary color; income/expenses always positive numbers (the label carries the sign) |
| Day groups | sticky-ish day header + that day's transactions | header: `Today`, `Yesterday`, else `Wed 29 Oct` — 12 pt caps `onSurfaceVariant`, row height 32 dp incl. spacing |
| Transaction row | category icon + name, memo as second line when set, amount right | height 64 dp; title 16 pt max 1 line ellipsized; memo 12 pt max 1 line; amount 16 pt tabular: expense `−$12.40` `onSurface`, income `+$2,400.00` primary |
| FAB | `+` | standard M3 FAB, bottom-end, 16 dp margin; only FAB in the app |
| Empty state | centered icon + "No transactions yet" + "Tap + to add your first one" | shown when the month has none; month switcher and balance strip stay visible (zeros) |

Sort: newest first; within a day, newest first (stable by insert order).
Delete: swipe-to-dismiss row → SnackBar *Deleted / Undo* (5 s, the undo reuses
the exact row id). Undo is the only delete safety net — no dialogs.

### 2.2 QuickAdd sheet

Modal bottom sheet, ~48 % height, no full-screen — with a 480 dp floor: the
3×4 keypad's keys keep the §3 touch-min, and where the two collide, touch-min
wins (48 % of a short screen would shrink the keys). Contents top → bottom:

1. **Segmented toggle** `Expense | Income` (M3 SegmentedButton, 40 dp) —
   expense preselected on a cold open; after a save the last toggle (and
   category) stay warm for the next QuickAdd (item 5).
2. **Amount** — large right-aligned text, 40 pt tabular, leading currency
   symbol 24 pt `onSurfaceVariant`; value `0` dimmed until first digit.
3. **Custom keypad** (3×4: 1–9, `.`, 0, ⌫) — no system keyboard ever covers
   this screen; keypad replaces the system one entirely.
4. **Category chips** — single horizontal scrolling row of FilterChips with
   icon+label; last chip `⚙︎` jumps to Manage → Categories; selected chip is
   remembered as *default for the next entry*.
5. **Save** — full-width filled button, disabled until amount > 0 **and** a
   category is selected. Save inserts (date = today, time = now), pops back to
   Ledger with the new row already visible at top, and leaves QuickAdd state
   (toggle, category) warm for rapid second entry — memo/date not required.

Optional fields behind one row of TextButtons above Save:
`Today ▾` (opens inline date strip: Yesterday / Today / calendar),
`Add note` (inline textfield, 48 dp, never steals the keypad — note entry
switches to system keyboard and back on blur).

### 2.3 Transaction detail sheet

Same sheet frame. Read-only stack: amount (40 pt), category chip, date/time
(12 pt caps), memo. Actions row: `Edit` (opens QuickAdd prefilled, Save
becomes Update) and `Delete` (danger text button → routes to the *same*
Undo-SnackBar path as swipe; **the app has zero delete dialogs** — Undo is
the one safety net, everywhere).

### 2.4 Manage

Plain list (no cards): **Categories**, **Base currency**, **About & help**.
Categories: two sections (Expense / Income), reorder by drag handle, tap =
rename icon/label sheet, add = sheet with icon grid (32 material icons, 4×8).
Base currency: picker of `core`'s currency list; note under it —
*"Used for balances display. Existing transactions keep their own currency."*
(decision 6).

## 3. Tokens (export to `ThemeData` 1:1)

| Token | Value | Use |
|---|---|---|
| seed | `#2E7D32` (existing `_seed`) | M3 `colorSchemeSeed`, light + dark |
| space-1…5 | 4 / 8 / 12 / 16 / 24 | margins; row horizontal padding = space-4 |
| row-height | 64 | transaction rows |
| label-caps | 12 pt, +0.4 tracking, `onSurfaceVariant` | day headers, stat labels |
| body | 16 pt `onSurface` | titles, amounts (tabular) |
| amount-hero | 40 pt tabular | QuickAdd, detail sheet |
| month-title | 22 pt | Ledger header |
| expense-sign | `−` (U+2212) | never ASCII hyphen |
| income color | `colorScheme.primary` | amounts + stat |
| expense color | `colorScheme.onSurface` | amounts (sign carries meaning — red stays reserved for destructive UI only) |
| radius-sheet | 28 (M3 default) | QuickAdd/detail |
| touch-min | 48 dp | every hit target incl. chevrons, chips padded |

Dark mode: same spec, no alternate palette; M3 dark scheme from the seed.
Contrast: all type passes AA at both brightnesses (M3 schemes guarantee;
golden tests pin the result).

## 4. Motion

Sheet: M3 modal default (256 ms emphasized-decelerate). Row insert: 200 ms
fade+slide from top. Month page: horizontal fade-through 300 ms. No other
motion; nothing loops.

## 5. Accessibility bar

- Everything reachable with TalkBack: rows are single semantics nodes
  ("Coffee, Lunch, 12 dollars 40 cents, Oct 29"), headers are section
  semantics.
- Supports system text scale to 1.3× without clipping (amounts shrink-wrap
  first via `FittedBox` on the hero amount only).
- No color-only meaning: expense/income always differ by sign **and** word.

## 6. Golden-test surface (harness scope)

Components pinned as goldens, rendered in CI (Linux, pinned Flutter floor):
`TransactionRow` (expense/income, memo/no-memo, long memo, scaled text),
`BalanceStrip` (zero month / typical / 7-digit), `QuickAddSheet` (empty /
entered+selected), `EmptyMonth`, light **and** dark for each. 20 goldens
total; generated by `--update-goldens`, reviewed in MR diff, then binding.

## 7. Deliberately *not* in E1

Budgets, receipts, import, search, multi-currency entry UI (add transaction
in base currency only until OFX work lands the picker), recurrence, backup,
iCloud/Android sync anything, ads, analytics, accounts/balance-tracking.
