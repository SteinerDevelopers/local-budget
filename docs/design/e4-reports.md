# E4 Design Spec — Reports (month · year · breakdowns · budget-vs-actual)

**Plan ref:** E4 (issue #5) — free-tier *standard analytics* (feasibility §3.4, §4.1.7).
Perf bar: charts at 60 fps on a mid-range device (issue #5, §4.2). Status: draft v1, 2026-11-02.

Governing rule (§3.4): reports are **free and complete for budgeting**; depth toys
(year-over-year, custom ranges, projection detail, multi-sheet exports) belong to the
paid analytics pack and must **not** leak into these screens as teaser stubs.

## 1. Information architecture — one new surface, two entrances

- New **Reports screen**: full-screen page pushed with `MaterialPageRoute` (scrollable
  analytics wants a page, not a sheet; back gesture is the exit).
- Entrance 1: the home screen has **no app bar** (decision 10 predates this spec's
  draft); its only persistent chrome is the month-header row. A trailing
  `Icons.insights_outlined` icon button (`Key('reports-open')`, Tooltip "Reports")
  joins that row after the forward chevron. The home light/dark goldens shift by
  that icon — regenerated in CI like every ref, no exceptions.
- Entrance 2: the Budgets sheet's month-header row gains the same icon after its
  forward chevron — opens Reports on the **Budget vs actual** segment
  (constructor arg `initialSegment`).
- No bottom navigation bar. The app's identity is one ledger screen + sheets; an
  epic does not get to change that (§4.5 decision 10). Segmented control *inside*
  Reports carries Month / Year / Budget-vs-actual.

## 2. Screens

### 2.1 Segment: Month (default)

- Header stepper `‹ November 2026 ›` (Key `month-prev` / `month-next`); the future is
  not navigable — forward arrow disabled at the current month.
- KPI strip (4 tiles, 2×2): **Spent**, **Income**, **Net**, **Pacing** — pacing is
  linear run-rate projected to month end, shown *only* for the current month
  ("On pace for \$X"); past months swap the tile to a per-day average for that
  month. Pacing is arithmetic, not advice (Help says
  so; no AI voice).
- **Category donut** (fl_chart `PieChart`): expenses in base currency, exclusions
  exactly as the budget engine's scope (no income, no goal transfers, refunds-as-
  income excluded — reuse `EngineTx` flags so reports can never disagree with the
  ledger). Center label = total spent. Tap a slice → **drill sheet**: that category's
  transactions for the month, rendered with the existing ledger row style.
- **Top merchants** list: top 5 by base spend with row counts ("Food Co · \$120.40 ·
  3"). Merchants exist only where capture/statement rows upserted them (§ E2);
  empty state is one honest line: "Merchant stats fill in as you scan or import."
  Manual QuickAdd rows have no merchant — by design, not a gap.

### 2.2 Segment: Year

- Year stepper (`2025 ‹ › 2026`); calendar year — matches the yearly budget period's
  `yearMonth = 'YYYY-01'` anchor.
- **Monthly bars** (fl_chart `BarChart`): 12 expense bars + horizontal average line;
  current month's bar uses the *accent* shade, complete months use primary. Tap a bar
  → jumps the Month segment to that month (state handoff inside the screen).
- **Top categories of the year**: 5 horizontal bars, share of year spend.

### 2.3 Segment: Budget vs actual

- One row per category budget of the selected month **plus the pinned overall target
  on top**. Bar = spent; marker = limit; status colors reuse the exact green/amber/red
  tokens the Budgets tab computes — single source: `BudgetEngine.statusFor` supplies
  every row. Rollover, when the device switch is on, draws a second ghost marker at
  the carry-adjusted available; otherwise nothing (no confusing empty markers).
- Zero-limit rows are hidden (a budget with no limit is a placeholder, not a plan).
- Empty state: "No budgets yet — set limits to compare." → pops to the Budgets sheet.

### 2.4 Charts — `fl_chart`, nothing else

- **`fl_chart` is the only chart dependency ever added** (single dep, tree-shaken,
  Dart-only). Donut + bars; no line charts (projection detail is paid).
- Perf contract for the 60 fps budget: aggregates are computed **before** `build`
  (async loader into a view-state), charts receive finished lists only; each chart is
  wrapped in `RepaintBoundary`; chart animations capped at 200 ms and disabled for
  data reloads (animate only on segment change). A dozen data points cannot drop
  frames by construction — the risk is recompute-per-paint, which this forbids.
- Verification: profile-mode manual pass on the emulator with `-dProfile` traces
  before M2 exit; no new CI job (headless profile runs flake — decision).

### 2.5 Help

- New 6th article **"Reports & privacy"**: segment walkthrough, what each stat counts
  (the engine's exclusion rules in plain words), the pacing caveat, and the zero-
  collection line — "every number here is computed on your device; reports were the
  last thing your phone ever analyzes." Search keywords: report, chart, pacing,
  merchant, donut.

## 3. Report semantics (pure Dart — `packages/budget`, new `reports.dart`)

`ReportEngine` mirrors `BudgetEngine`'s style: pure functions over `EngineTx` +
rows, no drift imports, fully unit-tested.

- `monthTotals(txs, month)` → `MonthTotals(spentMinor, incomeMinor, netMinor)`.
  Scope split by `countsTowardBudgets` / `isIncome` exactly like the engine.
- `categoryTotals(txs, month)` → rows `(categoryId, spentMinor, shareBp)` sorted
  desc; `shareBp` is basis points of spend (integer math; last slice absorbs
  rounding residue so shares sum to 10 000). Zero-spend months → empty list, the UI
  draws its empty state — division by zero never reaches the donut.
- `topMerchants(txs, month, {limit = 5})` → `(merchantName, spentMinor, count)`;
  null merchants skipped; ties broken by name asc (deterministic → goldens safe).
- `yearTotals(txs, year)` → 12 buckets `(yearMonth, spentMinor)` — missing months are
  explicit zero buckets so the bar chart always paints 12 bars.
- `pacing(txs, month, todayDays)` → `Pace(projectedMinor)?`: null when the month is
  complete or before day 1 (defensive; UI wouldn't ask). Formula
  `spent × daysInMonth ÷ dayOfMonth`, integer, clamped ≥ 0.
- Budget-vs-actual adds **no** new spend semantics: the screen calls
  `BudgetEngine.statusFor` / `overallStatus` per row and renders the result. One
  spend definition, two surfaces (Budgets tab and Reports can never disagree).
- Currency: base units only (`baseAmountMinor`), per §4.2 per-device base. Rows with
  unsynced FX show the ledger's existing "rate not synced" mark in the drill sheet —
  reports do not invent a second marker.

## 4. Merchant autocomplete (issue #5 checkbox 2)

- Lands where a merchant field already exists: the **capture review sheet** (§ E2).
  Below the field, up to 3 suggestion **chips**: prefix match (case-insensitive) over
  the merchants table, ranked by usage count desc, then most-recent use desc.
  New repo method `merchantsLike(prefix, {limit})` — one LIKE query, indexed enough
  at personal-scale row counts; no FTS.
- QuickAdd deliberately gains **no** merchant text field: the fastest flow stays
  keypad-first (decision 10). Manual rows simply have no merchant; stats and
  suggestions stay honest about that.

## 5. Schema

- **No migration.** Merchants (E2), transactions, and budgets cover every query.
  If a year with 50 k rows ever feels slow, the fix is a covering index — not a
  table. Decision: do not pre-build summary tables; personal-scale data in SQLite
  is a non-problem (feasibility §4.4).

## 6. Tokens & motion

- Donut/bar palette: 10-stop **categorical token ramp** (light + dark variants),
  cycled by rank, not by category id — rank-stable means the biggest slice is always
  stop 1 in every theme; documented in the tokens file like §4 colors elsewhere.
- Drill sheet: bottom sheet, existing sheet metrics. Segments switch with a 200 ms
  fade-through; no page-curl theatrics.
- Screen readers: donut → one list section, "Food, 42 percent, \$212.10" per slice
  (semantics override, fl_chart tooltips are pointer-only); bars read as a table
  ("November, \$1 204.00"). Contrast tokens unchanged.

## 7. Test surface

- Unit (`packages/budget`): month totals incl. engine-consistent exclusions; share
  basis-points sum to 10 000 incl. residue case; pacing on day 1 / mid / last day of
  February (leap); year buckets fill gaps; merchant tie-break determinism.
- Widget (app, in-memory db like E3): KPI tiles match seeded rows; donut tap opens
  drill with the right category; year bars count = 12 and tap navigates; budget-vs-
  actual pins the target and hides zero-limit rows; autocomplete chips rank and
  prefix-filter.
- Goldens (`test_goldens`): `reports_month`, `reports_year`, `reports_actual` ×
  light/dark → +6 refs (44 total), fixed-date seeds per the E3 pattern; refs via CI
  `goldens:generate` only.
- e2e: journey extends after the bill step — open Reports, expect the month KPI strip
  and a non-empty donut (presence asserts only, data-tolerant like the rest).
- a11y pass: SemanticsTester on the three segments; chart labels present.

## 8. Deliberately *not* in E4

- Year-over-year & custom-range comparisons — **paid** analytics pack (§3.4); the
  year segment is one year only.
- Cash-flow projection detail, recurring-charge detector — paid pack.
- Line charts, PDF/Excel report exports (CSV export stays free elsewhere).
- Report customization (reorder/hide cards), share-as-image, widgets.
- Summary tables / FTS / any schema change (§5).

## 9. Build decomposition

- **B1** — `ReportEngine` + full unit tests (`packages/budget`). Pure, lands green
  alone.
- **B2** — repo `merchantsLike` + review-sheet suggestion chips + tests
  (`packages/data`, `app/capture`).
- **B3** — Reports screen skeleton + Month segment (KPIs, donut, drill, top
  merchants) + widget tests; home month-header entrance.
- **B4** — Year segment + Budget-vs-actual segment + deep link from Budgets sheet +
  tests.
- **B5** — Help article, goldens (+6 refs), e2e journey extension, tokens doc.
  Closes #5 when green.
