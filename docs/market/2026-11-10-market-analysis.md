# Market analysis & 12-month revenue projection — Steiner Budget

_Deep dive 2026-11-10, from the app as it stands at main `9d77dac`
(receipts below). Two research sweeps (competitor landscape; funnel
benchmarks) run as cited subagent tasks; the capability ledger is this
repo's own measurement record. Every number carries its grade:_
**M** _vendor/study-measured,_ **E** _third-party estimate,_ **A**
_anecdote._ All projection numbers regenerate with the committed
instrument: `python3 scripts/market_projection.py`. This is a planning
document: pricing, store presence and promises remain owner-gated (Law 4);
recommendations here are options, not decisions._

---

## 1. Demand

**Category size (context only — not addressable):** personal-finance app
market estimates conflict by design: **$38.2B 2026, ~21 % CAGR**
([Luminix 2026, E](https://www.useluminix.com/reports/industry-analysis/competitive-landscape-personal-finance-and-budgeting-apps-2026))
vs **$25.8B 2026 → $167.6B 2035**
([BRI 2026, E](https://www.businessresearchinsights.com/market-reports/personal-finance-app-market-117811)).
The honest use of these is direction — big, growing, contested.

**The demand current that is ours:**

- **Subscription fatigue is measured, not vibes:** avg US consumer pays
  ~**$118/mo across 8+ subscriptions**
  ([Mastercard 2026, M](https://www.mastercard.com/us/en/news-and-trends/stories/2026/subscription-economy-fraud-deflect.html));
  incumbents keep climbing — YNAB $84→$99→**$109 + VAT**
  ([SheetLink 2026, M](https://sheetlink.app/ynab-pricing-2026),
  [r/ynab, A](https://www.reddit.com/r/ynab/comments/1vxrcq6/ynab_price_evolution/)),
  Monarch $99.99 + new **$199+ "Plus"** tier
  ([Finny 2026, M](https://getfinny.app/blog/monarch-money-pricing-2026)).
  "Budget apps without subscriptions" is now a self-maintaining Reddit/list
  genre ([Vault 2026, M](https://www.vaultbudgets.com/blog/budgeting-apps-without-subscriptions-2026)) —
  a shelf our exact shape fits and nothing big occupies.
- **Privacy distrust is durable and rising:** 65 % of US consumers are
  uncomfortable with AI use of their behavioral data; **48 % deleted an
  app in the past year over opaque data practices** (McKinsey 2026 via
  [LuckyFriday, E — primary not verified](https://luckyfriday.app/blog/privacy-first-budgeting-apps-what-they-are-and-which-ones-exist)).
  Aggregator distrust (Plaid, Mint→Credit Karma resentment) recurs on
  r/personalfinance
  ([2025](https://www.reddit.com/r/personalfinance/comments/1kqei5g/how_trust_worthy_are_plaid_linked_apps/),
  [2026](https://www.reddit.com/r/personalfinance/comments/1scao79/do_i_share_data_wit_credit_karma/), A).
  EPIC's CFPB complaint against Rocket Money over privacy claims
  ([Sep 2026](https://joindeleteme.com/blog/financial-literacy-month-2026-privacy-and-safety/), M)
  and banks fighting/feeing aggregators under Rule 1033
  ([RiaBiz 2025, M](https://riabiz.com/a/2025/11/8/jp-morgan-hustles-plaid-for-a-deal-in-bitter-fight-over-free-data-with-wells-and-pnc-encouraged-while-fidelity-schwab-also-force-fintechs-to-pay-up-or-pound-sand-as-part-of-deeper-digging))
  make the **sync-first model more expensive and unstable — our avoided
  architecture benefits directly.** ChatGPT Finances (US rollout Oct 2026,
  [OpenAI, M](https://openai.com/index/personal-finance-chatgpt/)) is the
  aggregator endgame; every privacy-panic headline it generates is free
  positioning for a literal "data is not collected" listing.
- **Mint refugees: narrative, not measured TAM.** ~3.6 M users left when
  Mint shut (Jan 2024, [USA Today, M](https://www.usatoday.com/story/money/personalfinance/budget-and-spending/mint-alternatives/90051260007/));
  Monarch's "20× subscribers" is the only capture datapoint and no 2025–26
  study measures refugee flows to offline apps. Treated as story, excluded
  from the projection.

**Demand verdict:** the intent exists and compounds in text ("budget app
no subscription", "offline budgeting", "receipt scanner no cloud"); what
it does NOT do in 2026 is find new apps by itself — organic Play discovery
for a zero-review listing is thin (§5). Demand is real; distribution is
the constraint.

## 2. Competition (Android, November 2026)

| App | Price | Cloud? | On-device OCR | Offline? | Notes |
|---|---|---|---|---|---|
| YNAB | $109/yr + VAT | required (Plaid/MX) | no | no | layoffs mid-2026, content decline ([SheetLink, M](https://sheetlink.app/ynab-pricing-2026); [r/ynab, A](https://www.reddit.com/r/ynab/comments/1tr3hol/ynab_content_gone_quiet/)) |
| Monarch | $99.99/yr, $199+ Plus | required | cloud/manual | no | 1 M members, $100 M ARR ([PR 2026, M](https://www.prnewswire.com/news-releases/monarch-hits-100m-in-arr-acquires-mbi-to-accelerate-next-phase-of-growth-302896004.html)) — the incumbent gravity |
| Copilot | $95/yr | required | no | no | **still Apple-only** ([measured, M](https://monavio.app/blog/copilot-money-for-android/)) |
| PocketGuard | $79.99/yr | first-class | no | no | premium $17.99/mo anchor ([M](https://pocketguard.com/blog/pocketguard-vs-everydollar-everything-you-need-to-know/)) |
| EveryDollar | free tier + ~$80/yr | cloud-first | no | manual-only free | Ramsey gravity, zero-based niche |
| Goodbudget | $80/yr | cloud | no | no | 10-envelope free cap |
| Spendee / Wallet | ~€4.49/mo+ | account required | no on-device | no | multi-platform, aging |
| Monefy | one-time Pro (est ~$12) | offline-usable | **no** | mostly | manual-only depth ceiling |
| Bluecoins | free + one-time Premium ~$4.99 (E) | own-cloud sync paid | **no** | yes | closest offline incumbent; dated UX, no rollover envelopes ([M](https://www.bluecoinsapp.com/settings/premium/)) |
| Money Manager (Realbyte) | ~$5 one-time | offline | no | yes | ~20 M installs (vendor claim), shallow engine |
| Actual Budget | free FOSS | self-host sync | no | self-host | weak native Android |
| Firefly III | free FOSS | self-host web | no | self-host | no official Android |
| **Leftovers** | **free FOSS (MIT, F-Droid)** | none — encrypted backup → Drive/WebDAV/Syncthing | **no (receipt photos, no OCR)** | yes | **most direct analogue 2025–26** ([F-Droid, M](https://f-droid.org/packages/com.leftovers.app/)) — widgets, BYO-key AI; month/year budgets only |
| **Steiner Budget** | free complete; Pro **$9.99 one-time** | none (own-cloud optional) | **yes — ML Kit + review, camera/PDF/screenshot** | yes | full envelope engine; statement import; E2EE own-cloud backup |

**The four-way gap is real:** no incumbent combines (a) offline-first +
(b) on-device OCR scanning + (c) full free budget engine + (d) one-time-paid
own-cloud E2EE backup. The closest, Leftovers, lacks (b) and the envelope
engine; Bluecoins lacks (b); Actual/Firefly lack (b) and native polish.
**But the moat is shallow:** OCR is commodity ML Kit, and the two most
credible rivals are free/FOSS — among privacy purists (exactly our
audience), "closed-source solo dev" must buy trust with receipts, not
brand. Our defensible edges, in order: the **review-first extraction
pipeline** (never-auto-commit + statement/bill routing, E11), the
**envelope engine**, the **measured polish process** (§3), and the
zero-data claim in its strongest literal form (free flavor has INTERNET
*removed at manifest level* — CI-guarded).

**Also true:** Play now requires a **financial-features declaration** and
is removing undeclared apps in rolling 2026 sweeps
([Apr](https://support.google.com/googleplay/android-developer/answer/16926792?hl=en)/[Jul 2026](https://support.google.com/googleplay/android-developer/answer/17134731?hl=en), M).
Nothing penalizes offline-first — but the declaration itself is a
launch-list item **currently uncovered in `docs/release/`** (grep: zero
hits) → filed as issue #54 against E9.

## 3. Capability & polish — us today, adjudicated, vs the field

The app's claims are bench-measured (this is unusual and it is a market
asset — nobody's competitor page can match "measured on named devices").

| Surface | Evidence (repo) | vs field |
|---|---|---|
| Receipt/bill/statement ingest | E2/E11 pipelines; bench-swept 2026-11-10; never-auto-commit law | **unique in niche** — Bluecoins/Leftovers/Monefy have no OCR; Leftovers stores photos only |
| Manual entry speed | QuickAdd ≤3 interactions, guarded; scan→save medians **32.9 s Flip6 / 45.1 s VERGE — over the 30 s bar on the manual fallback** ([bank](../release/measurements/2026-11-10/README.md)) | below our own bar; competitors' manual entry is slower (no measured claim anywhere beats us) |
| Budget engine | rollover/recurring/goals/weekly-yearly + CSV/OFX import free | beats every offline competitor; matches YNAB's envelope core without the $109/yr |
| Privacy | free flavor INTERNET-removed (CI `manifest-guard`); literal "data is not collected" | strongest form sold anywhere; FOSS rivals only *arguably* match |
| Accessibility | TalkBack pass both bench phones (0 clickable-unlabeled); font-scale 2.0 suite passing (MR !7/!8, today) | field does not publish or measure this at all |
| Perf | cold start Flip6 1304 ms / VERGE ~4.5 s; gfxinfo jank 21.4 % / 3.4 % — **re-run owed, bar <1 %** (Finding 5) | mid-range VERGE 3.4 % is close-ish; Flip6 number is the open wound |
| Test/gate discipline | 303 tests / 10 skips, goldens, emulator e2e, CI sole verdict | a solo-dev engineering moat; invisible to users, protective of the reviews we'll live or die by |
| Known gaps | merchant OCR quality (#44–46), draft persistence, E8 store content, RC gate unscheduled, **financial-features declaration (#54, new)** | each is a review-generator if shipped unresolved |

**Polish verdict:** above the offline-niche bar on every *measured* axis,
below our own bar on three numbers (manual-entry median, Flip6 jank,
camera first-run dialog). The field's published quality story is
zero measurements — our honesty (banking reversals, publishing Finding
5) is a differentiator among the exact audience that reads privacy
threads. Ship-readiness = the RC-gate list, not new features.

## 4. The marketing limitations — the projection's borders

All owner-set, all binding (this section is why the numbers look small):

1. **Play only.** No F-Droid, closed source (decision 12) — forfeits a
   channel that served **>18 M downloads/updates in 2025** to precisely
   our audience ([F-Droid 2026, M](https://f-droid.org/en/2026/01/23/fdroid-in-2025-strengthening-our-foundations-in-a-changing-mobile-landscape.html)),
   plus its review flywheel.
2. **US storefront only at launch** (owner ruling 2026-11-09). Cuts the
   highest-intent privacy demo (78 % of Germans say encryption matters
   [Proton 2025, M-survey](https://proton.me/learn/encryption/survey/germany))
   to ~zero.
3. **Zero ad spend, zero ad SDKs** (decision 4); **organic only.**
4. **Zero telemetry** — no attribution, no cohorts, no re-engagement;
   instruments = Play Console aggregates + reviews, nothing else.
5. **Revenue = Pro sibling listing ($9.99) + coffee-tip IAPs only**
   (amendment 2026-11-02); no subscription, nothing gated in free,
   grandfathered upgrades.
6. **Monetization waits for the business-account migration** (D&B issued
   → payments profile → closed testing → production); personal account
   hosts internal beta only, and *creating* anything monetizable there is
   forfeit ([runbook](../release/internal-beta-runbook.md)). **D&B timing
   undisclosed** → migration date is itself a scenario variable.
7. **iOS dormant until decision 11's trigger** (≥1,000 installs AND
   (D30 ≥20 % OR ≥10 paid sales), hard decision clock at month 6; E10:
   ships only on explicit owner go).

## 5. 12-month projection (Dec-2026 → Nov-2027)

Model: organic Play-only funnel; Pro sales from each month's install
cohort at the sibling-ratio; refunds assumed 8 % (E, unbenchmarked);
Play/Apple 15 % tiers. **Regenerate:** `python3 scripts/market_projection.py`.

**Input grades:** quiet-launch 90-day 200–1,500 installs (M/E:
[500-in-3-months solo case, A](https://www.reddit.com/r/androiddev/comments/1mqugsi/3_months_progress_of_my_first_android_app_hit_500/);
[niche launcher 890 total, M](https://www.appbrain.com/app/quiet-dumb-phone-launcher/com.ahkproduction.quietlauncher);
[80 % of apps <10 K/mo, M](https://appfigures.com/resources/insights/20230714?f=1));
sibling-ratio 0.5–2 % at full-free (E — Nova Prime 6.9 M/50 M ≈ 14 % is
the **feature-gated** ceiling, not our case); D30 5–7 % median, finance
~2 % ([Adjust 2026 via Core MBA, E](https://www.core-mba.pro/tool-hub/mobile-app-retention));
tips 0.05–0.2 % of MAU (E); elasticity −1…−4
([IJRM 2023, M-DiD](https://www.sciencedirect.com/science/article/pii/S0167718723000279));
spike +1–5 K one-hit, no forecastable probability (E).

| | **Low** (quiet launch, Mar-27 sales open) | **Base** (SEO compounding, Mar-27) | **Spike** (one community event May-27, halo +40 %, Jan-27) |
|---|---|---|---|
| Free installs (12 mo) | 1,425 | 4,150 | 9,827 |
| Pro sales | 7 | 33 | 138 |
| Android Pro net | $55 | $258 | $1,078 |
| iOS net (Sep-27+ base / Jul-27+ spike) | $0 (owner holds) | $51 | $270 |
| Coffee tips net | $60 | $153 | $298 |
| **Year net** | **≈ $114** | **≈ $461** | **≈ $1,646** |

Reading, honestly:

- **The band is $100–1,700 net.** This is the arithmetic of the
  limitations §4 — every one of them is an owner ruling, and the doc
  models compliance, not wishful breach. The feasibility doc's own frame
  holds: *craft + self-funding maintenance, not income* (§3.3).
- **The projection is migration-shaped.** Dec–Feb sales are structurally
  zero; pulling D&B/migration forward two months adds ~40 % to base-case
  revenue — the highest-leverage "marketing" act available is paperwork
  velocity.
- **The iOS trigger legs, measured:** D30 ≥20 % is a top-1–2 % outcome
  (finance D30 ~2 % — treat as unreachable); the **≥10 sales leg is the
  practical one** and fires in base by ~Sep and in spike by ~Apr. Month-6
  clock guarantees the *decision*, not the launch (E10 owner-go rule).
- **The ≥0.5 %-at-≥8k health gate is unobservable** in low and base
  (installs never reach 8k); in-year calls must use absolute sales
  thresholds instead — recommend the owner restate the gate at
  e.g. "≥15 Pro sales by month 6 of production".
- **Trademark payback ($2,100, 269 net sales):** spike case reaches it in
  November; base case in year 2. The marks were bought for the brand, not
  this year's cash.
- **Sensitivity:** at −1.5 elasticity the measured band says $5.99 yields
  ~29 % more Pro revenue than $9.99 and $12.99 ~12 % less. $9.99 stands
  (owner ruling) — but Play Console price tests are explicitly free
  experiment surface (pricing.md §Experiment), and the sensitivity table
  is the instrument's standing output.

## 6. Where we actually win (recommendations — owner gates marked)

_Monetization-specific levers, ranked, are §7._

1. **Ship-readiness first, features none.** Close #44–46 merchant quality,
   the manual-median and jank re-runs, E8 store content, RC usability gate,
   and **#54 (financial-features declaration)** before any date talk. In a
   zero-telemetry shop, the first 100 reviews are the entire instrument;
   they must land on a finished app.
2. **Migration is the revenue lever.** Chase D&B/paperwork as the top
   revenue-blocking task (owner-side). [Law 4-adjacent, owner executes]
3. **Play-search SEO is the only compounding channel** (~58 % of
   discovery, E): title/subtitle/keywords engineered for
   "budget — offline / no subscription / receipt scanner / no account"
   wordings; E8 listing copy should carry exactly these tokens.
4. **Earn, don't claim, the privacy trust the FOSS crowd demands:**
   publish the Data Safety screenshots, the manifest INTERNET-removal
   fact, and a "how we measure" page (the bank README's public-facing
   cousin). Closed source must pay the trust tax in receipts.
5. **Pre-position for the one-shot spike:** the median case needs the
   community event to reach $1k+. Prepare (not execute): Show-HN-ready
   post, r/privacy + r/personalfinance disclosure-honest drafts, press
   kit with the measured numbers. When it comes (unforecastable), the
   halo multiplier only exists if the listing converts same-day.
6. **Price test when volume allows** ($7.99 vs $9.99 vs $12.99 — free,
   console-side, zero code). [Law 4: owner rules any default change;
   grandfathering promise constrains everything upward.]
7. **Re-run this instrument** at production-open and at month 6 — the
   scenarios' value is the shape; recalibrate the curves against real
   Play Console aggregates (the only instruments we have or want).

## 7. Monetization upside inside the ethos

Every lever below passes all five tests: zero data collection stays
literal; free stays feature-complete; **paid only ever adds**; no ads, no
subscription; nothing that was free becomes paid. None requires an owner
reversal; a few need an owner ruling (marked). These are options, ranked
by expected value per unit of effort.

### A. Conversion, same installs (§5's curves untouched)

1. **Sell the promise on the Pro listing.** "One purchase. Yours forever —
   every future paid feature included, no upgrade ever. No subscription,
   no ads, nothing collected." The grandfathering + "more, never less"
   promises already exist ([pricing.md](../pricing.md),
   e6); they currently aren't the *pitch*. This is the only durable answer
   to free FOSS rivals: they can be cheaper, they cannot make a
   forever-promise with a signed receipt. Zero cost, listing-copy only (E8).
2. **Demo, don't gate.** The feasibility doc's own rule (§3.4: "the
   paywall page should *demo* the value"): free-app Settings carries an
   honest, non-nagging "What Pro adds" page — live widget previews on the
   user's own screen, a backup dry-run to their own storage, a sample
   YoY report. No locks, no countdown, no telemetry. A sibling listing
   converts on felt value the free app can now show.
3. **Make the handoff a selling point, not a footnote.** The
   signature-level ContentProvider transfer (e6 §3) is rare-craft: "tap
   *Transfer* in Pro — your data moves, nothing leaves the phone."
   Purchase anxiety for a data-heavy app *is* the objection; answer it on
   both listings with the mechanism, screen-illustrated.
4. **Launch into January.** Budget-search demand spikes in the first
   weeks of January (New Year's money behavior — the entire
   r/personalfinance cycle is seasonal); the migration gate may land
   there anyway (§5). If paperwork permits, first public week = first
   week of January 2027. Free, ethical, and plausibly the largest
   single install lever this side of the community-event lottery.
5. **Run the legal experiment loop.** Zero telemetry forbids in-app
   funnels, **not Play Console**: store-listing A/B experiments, price
   tests ($5.99/7.99/9.99 — the instrument's §5 sensitivity says lower
   never loses at launch trust levels; [Law 4 — owner rules the
   default]), and country rollouts all stay owner-side aggregates.
   (Precision for the skeptical reader: the zero-data promise governs
   *app-side* collection — the app ships no collectors of any kind;
   Play's own store-side listing reports exist for every developer
   before any install and leave the literal "data is not collected"
   answer true.)
   Monthly Console ritual: listing views→installs, sibling ratio, refund
   reason — the only instruments we have, and they are enough.
6. **Reviews are the instrument — earn them at launch.** Closed-testing
   testers (org account, runbook Phase 3) convert to day-one reviews by
   being asked honestly, once, in-product at a success moment. Review
   velocity feeds ranking; quality feeds conversion; both feed the spike
   lottery's landing page.

### B. The paid-pack flywheel (the promise as a growth mechanism)

7. **Ship fast-follow Pro rows on a drumbeat** (#12 menu: scan queue →
   multi-profile → tags/bulk → themes/icons). Every new paid feature
   *simultaneously*: adds a purchase reason (grandfathering means
   "buy now, get the queue free later" is a **real** urgency that FOSS
   can't counter), justifies the ruling's planned price step at iOS
   activation ($11.99–12.99 with Android rising — new buyers only,
   existing owners pay nothing ever again), and demonstrates "more,
   never less" instead of asserting it. Scan queue first: its buyer
   (landlord, freelancer, side-hustler) is the one who pays without
   convincing.
8. **Themes/icons/accents as the content factory** (§3.4's cheap row):
   lowest dev-week cost per new purchase reason, doubles as listicle
   bait ("the offline budget app that doesn't look like a spreadsheet"),
   and never touches a free promise because cosmetics were never free
   to begin with.
9. **Line-items (v2) stays paid-first** — the §3.4 reservation already
   reserves it; hold that line exactly as written.

### C. Trust artifacts that market themselves

10. **Publish the receipts.** A "How we measure" page: the bank README's
    public cousin — device names, dated screenshots, the *reversed
    Finding 2* story told as process virtue. Closed source pays its trust
    tax with auditable honesty; privacy-audience buyers convert on
    receipts, and both listings can link it.
11. **Manifest as marketing:** "The free app has no internet permission
    — enforced at build." CI-guarded (`manifest-guard`), verifiable by
    the user in their own permission screen. Nothing else on the Play
    finance shelf can say this; say it in the first three lines of
    copy.
12. **Honest-comparison page** (Steiner vs subscription incumbents vs
    FOSS analogues — including what Leftovers does better: free, FOSS).
    Naming the FOSS rival honestly is exactly the tone the audience
    rewards, and pre-empts the one objection that kills Pro conversion.

### D. Small mechanics, flagged for completeness

13. **Coffee tips via Play cost 15 %;** a US storefront BMC link-out
    currently keeps 100 % ([feasibility §3.2](feasibility.md), post-2025
    rules) but carries review-risk flux — keep IAP tips at launch
    (e6 tiers), reconsider link-out only if tips ever exceed the
    trivial band. [Law 4 — promise copy.]
14. **Refunds (8 % assumed) shrink with expectation-setting:** the demo
    page (A2) and transfer page (A3) are also refund preventers.

### Not monetization plays — the guard list

For the record, these all raise the modeled numbers and are **rejected on
ethos**, so a future session doesn't re-litigate them: subscriptions or
"Pro+" tiers above existing Pro (breaks grandfathering); moving anything
free behind Pro (breaks the headline promise); any paid feature that
expires; nag screens/first-run paywalls (the free app is the advert, not
the funnel); telemetry-gated funnels or A/B beyond Play's own console;
ad SDK "just for attribution"; F-Droid/sideload channels (decision 12 —
owner-gated, and the only listed item here where the owner's *yes* would
change anything).

## 8. Corrections to our own record (from this sweep)

- `docs/pricing.md` measured-basis line: "**Bluecoins+ … ~$7–10 Android**"
  — measured now: **Android Bluecoins is free + one-time in-app Premium
  (~$4.99, E), not a paid sibling listing** ([vendor, M](https://www.bluecoinsapp.com/settings/premium/));
  the iOS Bluecoins+ paid-app precedent may still stand. The $15.99-iOS
  anchor survives, the Android mechanics description does not. Fix at the
  next pricing pass (owner-gated doc).
- The sibling-ratio inputs here use the corrected picture (full-free app
  with zero in-app prompt → low end of 0.5–2 %).

## 9. Bottom line

Demand for exactly this app is real and rising (subscription fatigue +
privacy backlash + aggregator instability). The competitive slot is
genuinely open (no four-way incumbent). The product's measured polish
already beats the offline niche on every axis it publishes. **The binding
constraint is distribution inside self-imposed limitations** — so the
12-month revenue projection is deliberately modest ($100–1,700 net;
expected value ~$500) and the same limitations make the *strategic* payoffs
non-linear: a single community moment, the iOS activation, or a listicle
placement can 3–5× the year in one jump, which is precisely what the
decision-11 trigger is built to catch. Ship the finished app; the math
follows the paperwork and the moment.
