# E3 Design Spec — Budget Engine (periods · envelopes · bills · goals)

**Status:** Design-first deliverable per decision 10. Binding: implementation may
not invent layout/color/behavior not described here; deviations are spec edits
first, code second. This epic delivers the **free** budget engine (decision 7:
the engine is feature-complete in the free tier). All money math reuses
`packages/core` `Money`/`Amount` integer minor units; all comparisons happen in
the device base currency (decision 6) via the existing `baseAmountMinor` column
— E3 adds no per-account bases and no automatic FX fetches (decision 8).

Design principles inherited verbatim from E1 §0 — one-handed, quiet chrome,
offline truth. **The frame does not move:** E3 adds no bottom destination and
no new nav hop deeper than one sheet.

---

## 1. Information architecture — one new surface, two entrances

```
Ledger (home)
├── tap on the Expenses stat in the balance strip ─┐
├── Manage sheet item "Budgets & bills" ───────────┤
│                                                  ▼
└── QuickAdd / Detail sheets (unchanged)   Budgets sheet (full-height modal)
                                            ├── segmented: Budgets | Bills | Goals
                                            ├── month switcher (same control as home)
                                            └── editor sheets opened from each tab
```

The Budgets sheet is the E2 Review sheet pattern again: `DragHandle` +
full-height `showDraggableSheet`, back closes. Segmented control = M3
`SegmentedButton`, 40 dp, labels 14 pt. The month switcher inside it is the
same widget/interaction as home §2.1 and pages **only within the sheet** — it
never moves the home month (and vice versa; the sheet opens on the home's
current month, per period type §3).

## 2. Screens

### 2.1 Budgets tab (default)

Top → bottom:

| Zone | Content | Spec |
|---|---|---|
| Overall target | `Spent $842.10 of $1,200.00` + 6 dp bar | target row tappable → inline numeric sheet (same keypad as QuickAdd). No target set → `Spent $842.10` only; bar hidden. Over target: bar + value `error` color, never a warning icon |
| Category rows | icon, name, `spent / limit`, thin progress bar | row 56 dp; bar 4 dp under the name baseline, radius 2; fill = min(spent/limit, 1); **overspend keeps the fill at full and colors it `tertiary`** — the number carries the truth (`$130 / $100`). Tap → category limit editor |
| Carry-in badge | `+$20 from Oct` / `−$12 from Oct` suffix on the limit | only when rollover is on for that month (§3.3); 12 pt `onSurfaceVariant`; the effective limit is what the bar divides |
| Footer | `Add category budget` + `Rollover` switch | the switch writes Settings key `budget_rollover` (device-wide, default off); the editor lists only categories without a budget yet |

Empty state: icon + "No budgets yet" + "Add one to track a category this
month". Months with transactions but no budgets still show the empty state —
budgets are opt-in per month, never auto-copied (copy-last-month is the footer
action `Copy October's budgets`, shown only when last month had any).

### 2.2 Limit editor (sheet, ~40 %)

Category chip (name + icon, preselected when opened from a row), period-type
segmented `Monthly | Weekly | Yearly` (default Monthly; other types create an
independent budget row for the same category), amount field = QuickAdd keypad
with the device base currency symbol, Save / Delete. One category may hold at
most one budget **per period type per period** (unique index §4); re-saving the
same period overwrites. Limits are stored in base currency minor units;
changing the device base currency later does **not** rewrite old limits
(documented: budgets follow the currency you typed them in — same rule E1 set
for the ledger).

### 2.3 Bills tab

| Zone | Content | Spec |
|---|---|---|
| Due rows | icon, name, `Due Wed 5 Nov`, amount | row 56 dp; overdue = date in `error`, due-within-3-days = `onSurface` bold; sorted overdue → soonest; completed occurrences fade the row out of the list (§3.4) |
| Row tap | occurrence detail sheet | shows `Mark paid` / `Edit rule` / `Delete rule` |
| Footer | `Add bill` | rule editor below |

**Bill rule editor** (full-height sheet): name (text), amount (keypad, base
currency), frequency segmented `Weekly | Monthly | Yearly` + day semantics
(weekly: weekday chips; monthly: day-of-month number, clamped 28–31 allowed);
category chip; `Notify` switch (default on, §5); start date (month switcher
pattern). Bills are **not** transactions: they are rules; marking paid writes
a real transaction through the exact repository path QuickAdd uses (§3.4).

### 2.4 Goals tab

Rows: icon, name, `saved / target`, progress bar (same geometry as §2.1).
Editor: name, optional target amount (blank = open-ended), note. Row tap →
detail: progress, transaction list of its transfers, `Add to goal` / `Withdraw`
keypad sheets. A goal movement is a transaction row with a reserved
`goalId` column, `source = manual`, and it is **excluded from both balance
strip and budgets** (§3.5) — a transfer, not income or expense.

### 2.5 Help

One new article `Budgets, bills & goals` in the existing help index (search
picks it up automatically): what rollover does and doesn't do, why goal
transfers are hidden from the ledger strip, how reminders work (§5).

## 3. Engine semantics (pure Dart — new `packages/budget`)

UI and repositories stay dumb; every rule below lives in a pure package with
integer arithmetic and injected `DateTime now`, mirroring `core`'s test style.

1. **Periods.** `monthly` = calendar month of the sheet's visible month;
   `weekly` = the ISO week containing the visible month's *1st* unless the
   sheet is switched to week granularity — **v1 ships month granularity
   only** (period-type rows still compute: a weekly budget shows progress for
   the ISO week containing the visible month's today; the switcher stays
   month-level); `yearly` = calendar year of the visible month. Spent = sum of
   `baseAmountMinor` (non-goal, non-income) transactions whose `dateDays` fall
   in the period, **across all accounts**, converted at save time by the
   stored `fxRate` (never re-converted later).
2. **Budget matching.** Category budget covers its category only (children
   included when a taxonomy depth >1 exists; v1 taxonomy is flat — E1 rule
   kept). Overall target = all expenses of the period.
3. **Rollover** (device-wide switch): effective limit = limit + carry, where
   carry = (previous period's effective limit − previous spent) for the same
   category chain, **bounded**: carried surplus ≤ the limit (never grows past
   2×), carried deficit passes through whole (a $50 budget overspent by $80
   starts at −$30). Periods with no budget row break the chain. Rollover
   never reaches into goal transfers.
4. **Recurring materialization is lazy.** Opening the app (cold or warm
   resume) runs one local pass: rules whose `nextDue ≤ today` get a
   transaction inserted *as if typed by the user* (source `manual`, note
   `Bill: <name>`), and `nextDue` advances; missed months materialize
   **one per app-open**, oldest first — never a silent backfill dump.
   `Mark paid` is the immediate, explicit version of the same insert. A
   rule whose next occurrence is >365 days after the last materialization is
   surfaced as "paused?" instead of inserting.
5. **Goal exclusion.** Transactions with `goalId != null` are hidden from the
   ledger day groups **and** the balance strip and the budget "spent" sums.
   They appear only in the goal detail. (They remain in exports — E5.)
6. **Base currency.** Reading limits/progress uses the stored values as-is;
   §2.2's no-rewrite rule applies here too.

## 4. Schema (drift migration v1→v2)

- `Budgets`: add `periodType TEXT NOT NULL DEFAULT 'monthly'`, `goalId` unused;
  drop the implicit single-per-category assumption → unique index
  `(categoryId, yearMonth, periodType)`. Add `rolloverCapMinor INTEGER NULL`
  (per-category override, nullable; UI does not expose it in v1 — schema room
  for E4's "cap carry" ask).
- `Transactions`: add `goalId INTEGER NULL REFERENCES goals(id)`.
- New `RecurringRules`: `id, name, amountMinor, currencyCode, categoryId,
  frequency TEXT, dayOfMonth INTEGER NULL, dayOfWeek INTEGER NULL,
  startMs, nextDueMs, notify INTEGER default 1, archived INTEGER default 0`.
- New `Goals`: `id, name, targetMinor INTEGER NULL, currencyCode, icon TEXT
  NULL, archived INTEGER default 0, createdAtMs`.
- Settings keys (no table): `budget_rollover` (`on|off`),
  `bills_last_materialize_ms`.

## 5. Notifications — local only, honest about Doze

`flutter_local_notifications` (exact-alarm permission NOT requested — the
inexact window path is the default). On materialize-or-mark-paid we schedule
the **next** notification: bill day 09:00 local ±60 min window; tapping opens
the app and shows the bill detail sheet. No background service, no push, no
network (decision 8 — the promise stays literal). Because Doze may deliver
late, the sheet's "Due" rows are the truth and the notification is the hint;
the Help article says exactly that.

## 6. Tokens & motion

No new tokens (E1 §6 still holds): progress fill `primary`, over-target fill
`tertiary`, overdue `error`. Bars animate 200 ms `easeOut` on value change —
same motion curve as E1 sheets. New goldens (×2 themes): budgets empty,
budgets with rows + rollover badge + one overspent, bills list, goal detail;
plus a refresh of the home-set is **not** needed (home does not change).

## 7. Test surface

- `packages/budget`: pure unit tests — period math (leap Feb 29, 31-day clamp
  to Feb, ISO week edges), rollover bounding, lazy materialize ordering
  (missed-3-months = 3 opens), goal exclusion sums, base-currency summation
  with mixed currencies. Golden JSON fixtures like core's `receipt_goldens`.
- Data: drift migration test (v1 rows survive, unique index rejects
  duplicates), repository round-trips for rules/goals.
- App: widget tests per §2 sheet (tap-expense → sheet opens; segmented switch;
  rollover badge text; mark-paid writes a ledger row visible on home).
- e2e: one extended journey — add expense on home → budgets tab shows it in
  the category progress → add bill → mark paid → row appears on home.

## 8. Deliberately *not* in E3

Reports/charts (E4); tags & bulk edit; per-account base currency (decision 6);
auto-FX rate lookup at save (user may still type a rate — E1 rule kept);
cloud sync, notification inbox, budget copy scheduling; multiple currencies
per budget (budgets are base-currency only); income budgeting; widgets
(paid pack, decision 9); iOS device validation beyond compile (decision 11).

## 9. Build decomposition

| # | Issue | Delivers |
|---|---|---|
| B1 | `packages/budget` engine core | §3 + pure tests, zero Flutter |
| B2 | Schema v2 + repository | §4 + drift migration test, repo CRUD |
| B3 | Budgets tab + limit editor | §2.1–2.2 UI on the engine |
| B4 | Bills tab + rule editor + local notifications | §2.3 + §5 |
| B5 | Lazy materialization + mark-paid path | §3.4 wiring into app start |
| B6 | Goals tab + goal transactions | §2.4 + §3.5 |
| B7 | Rollover + period types surfacing | §3.1/§3.3 UI affordances |
| B8 | Help article + goldens + e2e journey | §2.5/§6/§7 closure |
