# Project Plan — Steiner Budget

**Companion doc:** [feasibility.md](./feasibility.md) — the full feasibility & requirements study (11 decisions). This plan operationalizes it.
**Status:** Planning · **Date:** 2026-11-02 · **Team:** solo dev (+ AI-assisted build sandbox)

---

## 1. Elevator spec

Offline-first, zero-data receipt-scanning budget app. **Android launches publicly; iOS is built continuously from day 1 and *activated* when the traction trigger fires (decision 11).** Free tier is feature-complete; a one-time $7.99–$12.99 unlock sells value-adds (own-cloud backup, widgets, analytics pack — decision 9); no ads, ever (decision 4). The UI quality bar (§4.5 of the feasibility doc) is binding (decision 10).

## 2. Decision snapshot (full rationale in feasibility §7)

| # | Decision |
|---|---|
| 1 | English UI at launch, multi-currency amounts, locale-aware internals |
| 2 | Header-level extraction in v1; `line_items` schema reserved for v2 |
| 3 | CSV + OFX statement import in v1, free |
| 4 | **Ads dropped entirely** — zero ad SDKs, literal "data is not collected" store forms |
| 5 | One receipt per import review (paid scan queue = batch *in*, still 1-review-per-receipt) |
| 6 | Base currency set once per device |
| 7 | Free tier is feature-complete; paid only ever adds |
| 8 | Zero data collection/sharing — absolute |
| 9 | **Launch paid pack:** own-cloud backup + widgets + analytics pack |
| 10 | Design-first: prototype validated before build; usability gates at MVP & RC |
| 11 | Build both platforms; defer heavy iOS testing/launch until "has legs" trigger |
| 12 | **No F-Droid, source stays closed** — Android distribution is Google Play only; no open-source publication obligations (owner decision, 2026-11-07) |
| 13 | **Self-signing, hybrid (Play excepted)** — the owner holds the app signing key for every channel except Google Play, where new apps are *required* to use Play App Signing (Google-managed app-signing key since Aug 2021); our key doubles as the Play **upload key** (auto-registered by first accepted bundle). Custody = age-encrypted blob in two independent cloud buckets (two regions) + passphrase split (password manager & safe deposit box); annual restore drill. Direct APK & any future non-Play store keep the one true signature (owner decision, 2026-11-07; hybrid amended same day when Play's mandate was confirmed) |
| 14 | **Product icon = "minted sprout" (v1-ring)** — white sprout inside a coin-ring on brand green `#1e5c46`, pure vector (SVG masters → resvg renders; QA gates: 48 px actual, squint, round-mask, themed mono, wallpaper worlds); selected from 24 AI concepts + 8 hand-authored variants by measurement — the runner-up "sealed arc" died on real power-button adjacency at 48 dp. Brand tiers: company keeps the letter-"S" mark (site/favicon), products get glyphs in the one family palette (owner decision, 2026-11-07) |
| 15 | **Agent playbook is rule zero of every development cycle** — before code, plans, or environment assertions, an agent pulls `Steiner-Bot/agent-playbook` and reads the doc matching the task (map in [AGENTS.md](../AGENTS.md)); transferable lessons are written back to the playbook in the same shift they are learned, project facts stay in this repo. Precedence when sources disagree: measured platform reality > playbook > repo docs > session memory. Born of documented near-misses: a mechanism reinvented two pages from its own answer, and Play policy assumed a month after it changed (owner decision, 2026-11-07) |
| 16 | **Product name = Steiner Budget, everywhere the user reads; wire identities frozen** — prose, store metadata, docs, widget and report headers all say Steiner Budget. Never renamed: applicationId `dev.steiner.local_budget` (the Play package-lock event plus every installed kit hangs on it), internal identifiers (`LocalBudgetApp`, `bootLocalBudget`, Kotlin/Dart class names), repo path `local-budget-app`, backup magic `LZBK1`. A wire identifier is a data/store contract, not a label — renaming one is a breaking change wearing a disguise (owner decision, 2026-11-08) |
| 18 | **License = keep AGPL-3.0, hedge the relicense door** — app code stays AGPL-3.0: §13 network clause blocks hosted-fork capture of a privacy product, strong copyleft is the trust signal for the audience we court, and the binary+Pro model pays no copyleft tax while copyright stays 100 % LLC-side. Hedge (the part that decays if postponed): `CONTRIBUTING.md` records agent-commit provenance (LLC work-for-hire), requires DCO sign-off, and takes a relicense grant from every future outside contribution — preserving the MPL/dual-license option while the history is still third-party-free. Number 18 after collision-check: 17 is the UX ruleset (playbook ledger) (owner ruling "keep and hedge", 2026-11-13) |

## 3. Timeline & milestones

Solo experienced dev. Weeks are ranges with the decision-driven extras already priced in (feasibility §6).

| Milestone | Weeks | Scope (exit criteria in bold) | GitLab milestone |
|---|---|---|---|
| **M0 · Design** | 1–3 | Figma design system + interactive prototype of the 4 core flows (scan review, manual entry, budgets, reports); **5-tester validation passed; §4.5 acceptance targets signed off as spec** | `M0 · Design` |
| **M1 · MVP (Android)** | 4–13 | Manual entry w/ custom numeric pad; camera/PDF scan → OCR → review → save; monthly budgets; basic reports; CSV export + local backup. **MVP usability gate (§4.5) passed on mid-range Android** | `M1 · MVP` |
| **M2 · v1.0 Android launch** | 14–26 | Full free budget engine (rollover, recurring + reminders, goals, weekly/yearly); standard analytics; CSV/OFX import; Help section; **paid pack (own-cloud WebDAV/Drive backup, widgets, analytics pack) + unlock IAP**; tip link; RC usability gate; Data Safety forms; **live on Google Play** | `M2 · v1.0 Android` |
| **M3 · Fast-follows** | post-launch | Demand-driven paid menu rows (§3.4): scan queue, tags/bulk tools, multi-profile, themes; retention/KPI review | `M3 · Fast-follows` |
| **M4 · iOS activation** *(conditional)* | +3–5 at trigger | VisionKit scanner & share extension; Cupertino/§4.5 pass; TestFlight beta; StoreKit unlock + iCloud backup target; Foundation Models validation; **live on App Store** | `M4 · iOS activation` |

**Parallel cheap lane from week 1 (decision 11):** path-filtered `flutter build ipa` + weekly headless-simulator smoke run (scan→review→save→budget) keep iOS provably alive at near-zero macOS cost.

## 4. Workstreams → epics

Each epic = one GitLab issue with a task checklist. Labels: `epic` + `phase::*` + `area/*`.

1. **E0 Foundations & CI** (`phase::build`, `area/infra`) — Flutter scaffold, drift schema w/ `line_items` reserved + `source` discriminator, money-as-minor-units type, design tokens, repo hygiene; self-hosted runner on the R5-5560U mini PC (KVM, `kvm` group, restricted runner group); Android emulator CI (headless, x86_64 only); iOS-parked CI lane; golden-test harness.
2. **E1 Design system & prototype** (`phase::design`, `area/ui`) — Figma system, interactive prototype, 5-tester validation, motion & accessibility spec, custom numeric-pad + review-sheet designs (the two make-or-break surfaces).
3. **E2 Capture pipeline** (`phase::build`, `area/capture`) — camera scan + edge detection/crop; ML Kit OCR tier; heuristic TOTAL/date parser; editable review sheet w/ uncertainty highlights; Photos/screenshot import; share-sheet/file-open intake; PDF (text-layer + page-render OCR); tier-3 Gemini Nano w/ feature detection + graceful degradation; screenshot quick-pick.
4. **E3 Budget engine** (`phase::build`, `area/budgets`) — transactions CRUD, categories editor, accounts, monthly budgets + rollover, recurring bills + local notifications, goals, weekly/yearly periods.
5. **E4 Reports (free standard)** (`phase::build`, `area/reports`) — month/year views, category & merchant breakdowns, budget-vs-actual, simple charts; free-tier boundary respected (§3.4).
6. **E5 Data layer** (`phase::build`, `area/data`) — CSV export, encrypted local backup/restore (SAF), CSV import w/ per-bank column-mapping profiles + conservative dedupe, OFX parser, FX-rate lookup w/ offline degradation, per-device base currency.
 7. **E6 Monetization (v2, decision 12)** (`phase::build`, `area/monetize`) — **no unlock/one-time IAP ever ships**: the only IAP is the coffee-tip consumables (`lb_coffee_small/medium/large`, zero gating); the paid tier is a **separate paid store listing** (flavor `pro`, `applicationIdSuffix .pro`) with a data-preserving free→paid transfer (export→import handoff, no cloud, no accounts); nothing named `unlock` exists in code; Help section carries the coffee + upgrade flows.
8. **E7 Paid pack (launch trio, decision 9)** (`phase::build`, `area/paid-pack`) — scheduled versioned backup to user's own WebDAV + Google Drive (first; iCloud at M4); home/lock widgets (spend-this-month, envelope-left, quick-scan); analytics pack (YoY/custom ranges, recurring-charge detector, PDF/Excel export).
   *Shipped on main 2026-11-03 as WebDAV-first per owner note 164 on #8 — the Drive
   destination waits for post-launch; widgets, insights and exports are in.*
9. **E8 Help & content** (`phase::build`, `area/content`) — searchable offline Help (bundled articles + an in-memory inverted index — shape recorded in #9 note 172) covering every screen + scan-quality tips + import guide; privacy policy; store listing copy; category taxonomy + copy pass.
10. **E9 Release (Android)** (`phase::release`, `area/release`) — RC polish vs §4.5 checklist; RC usability gate (5 testers, retention-blockers fixed); Data Safety "data is not collected" form; permission purpose strings; Play internal → open beta → production; fastlane.
11. **E10 iOS activation** *(conditional, decision 11; re-confirmed parked 2026-11-03 — no Apple Developer account yet, iOS ships only on an explicit owner go, and every slot before that stays on Android polish/beta)* (`phase::ios`, `area/ios`) — VisionKit scanner + share extension + photo picker; Cupertino-adapted §4.5 pass + accessibility matrix; **separate paid App Store listing mirroring decision 12 (no unlock IAP on any platform; coffee tips are the only IAP)**; iCloud Drive backup target; Foundation Models tier validation on Apple-Intelligence hardware; TestFlight round; App Store submission (privacy labels: no collectors); Xcode Cloud / rented-macOS CI lane (§6.1).
12. **E11 Document import — bills & statements** (owner request 2026-11-04, decision 13) (`phase::build`, `area/capture`, `area/data`) — "Photo or PDF" row in the E5 import wizard routes on-device (`DocType` heuristics): bank statements → parsed rows on the shared Preview (E5 dedupe + bulk commit, `statementImport`), bills/invoices → `BillPrefill` into the E3 editor (1:1, review-first per decision 5); multi-page text extraction; benchmark scripts + Help article. Spec: `docs/design/e11-document-import.md`.

## 5. Testing plan (per feasibility §6.1)

| Tier | Where | Cadence |
|---|---|---|
| Dart unit (money, FX, parsers, dedupe, drift queries) | dev sandbox + CI | every push |
| Widget + golden (§4.5 UI surfaces) | CI headless | every push |
| Android E2E (`integration_test` on headless emulator, KVM) | self-hosted mini-PC runner | every merge to main |
| iOS build + simulator smoke (scan→save→budget) | rented macOS lane (Xcode Cloud free 25 h/mo or GH macOS, path-filtered) | on `ios/` changes + weekly |
| Real devices (§4.5 usability gates, camera OCR, on-device AI) | physical phones / TestFlight | MVP gate + RC gate + betas |

## 6. Risk register (top rows; full list in feasibility §4.4)

| Risk | Mitigation (owner: dev) |
|---|---|
| Frustrating UI sinks great guts | Decision 10 process: prototype-before-build, usability gates, §4.5 checklist at RC |
| iOS silently rots while parked (decision 11) | Weekly simulator smoke + path-filtered iOS builds; activation estimate assumes green, re-baseline if smoke has been red >2 wks |
| "Has legs" trigger drifts into *never* | Open question #4: set thresholds **and a hard clock cap (~month 6)** at end of M1 |
| OCR errors create a correction-death-spiral | Never auto-commit; uncertainty-highlighted review; heuristics per locale; LLM tier where available |
| Paid pack converts too weakly | Flagship trio + demo paywall; treat app as self-funding maintenance, not income (§3.3); supporter/BMC fallback |
| Self-hosted runner abuse | Restricted runner group (trusted triggers only), isolated OS, no long-lived secrets on box |
| Scope creep before launch | Anything not in §4.1/E0–E9 lands in M3 backlog issues |

## 7. KPIs & the iOS activation trigger (proposed — confirm by end of M1)

- North-star: **weekly users who log ≥1 real expense** (privacy-first apps can't see more; Play Console aggregates are the instrument).
- Health: D30 retention ≥ 20 % · store rating ≥ 4.5 · crash-free sessions ≥ 99.8 % (local counts, no telemetry needed for the gate itself) · unlock conversion ≥ 0.5 %.
- **iOS activation fires when:** Play ≥ 1,000 installs **and** (D30 ≥ 20 % **or** ≥ 10 unlock sales) … **or unconditionally at month 6 after launch.** On fire: schedule M4 (+3–5 wks), start TestFlight, spend TestFlight/device-farm budget.

## 8. Repo layout & conventions

```
local-budget-app/
  docs/                  feasibility study, this plan, decision log
  app/                   Flutter app (android/, ios/ kept buildable both)
  packages/              core domain (pure Dart: money, parsers, dedupe) + data (drift)
  .gitlab-ci.yml           stages: test (analyze/unit/widget), e2e-android, ios-parked
  TOOLING.md             runner setup, sandbox notes (this workspace), emulator flags
```

- Conventions: conventional commits; `main` protected, PRs on AI-assisted work; every epic issue gets sub-issues or checklist tasks; decisions beyond the 11 get a numbered entry in the feasibility §7 table before implementation.
- The AI dev sandbox runs the Dart unit/widget tiers + APK builds directly (feasibility §6.1); emulator E2E lives on the mini-PC runner.

## 9. First 10 actions (week 1)

1. Create GitLab project (this repo), labels, milestones, epic issues ✅ *(done — see issue board)*
2. Install Flutter + JDK + Android SDK in the sandbox; scaffold `app/` + `packages/core`.
3. Stand up the mini-PC runner: Linux, `gitlab-runner` service, KVM group, restricted runner group. *(first runner already live — see below)*
4. CI: GitLab CI `test` stage (analyze + unit + widget + golden) and `e2e-android` stage (headless emulator template).
5. iOS-parked CI lane: path-filtered `flutter build ipa` + weekly simulator smoke (start spending the Xcode Cloud 25 h/mo).
6. Drift schema v1 incl. `line_items` reserved + `source` discriminator + currency columns (decision-6 proof).
7. Figma file + design tokens; first pass at numeric pad + review sheet.
8. Draft §4.5 acceptance checklist as an executable golden-test list.
9. Create M3 backlog placeholder issues for the deferred paid-menu rows.
10. Set the iOS-trigger confirmation as a calendar item for end of M1 (open question #4).
