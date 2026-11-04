# Feasibility & Requirements — Local-First Receipt/Bill Budgeting App (Android + iOS)

**Status:** Exploratory feasibility study (no implementation)
**Date:** 2026-11-01
**One-line verdict:** Feasible with today's mainstream tooling. OCR + on-device AI structuring, camera document scanning, and fully local storage are all proven on both platforms. The two real constraints are (1) iOS gives you *manual* screenshot/photo import only — no automatic ingestion — and (2) monetization must lean on a one-time paid unlock plus Buy-Me-a-Coffee-style tips; **ads were considered and dropped** (§3.1), keeping the zero-data promise absolute.

---

## 1. Product summary

A budgeting app that:

- Works **entirely offline/local-first** — no account, no cloud; user data never leaves the device (the only network touches are optional live FX-rate lookups and paid backup to the user's *own* cloud storage).
- **Ingests bills & receipts** from three channels: **camera** (live document scan), **screenshot/photo import**, and **PDF** (email attachments, e-receipts, statements).
- Extracts **merchant, date, total, currency, category** (and best-effort line items) from the captured image/PDF, then shows an **editable review screen** before saving.
- Provides clean budgeting — accounts, categories, monthly budgets, reports/charts, search, CSV export, local backup — behind an **exceptionally polished UI: a binding quality bar (§4.5, decision 10), because no matter how good the guts are, a frustrated user is a lost user**.
- Ships a **detailed in-app Help section** covering every function.
- Monetized by a **one-time paid unlock** carrying value-add improvements (§3.4) plus an optional **"Buy Me a Coffee" tip link**; **no ads** (§3.1).

---

## 2. Technical feasibility by capability

### 2.1 Cross-platform framework — ✅ proven, pick one codebase

| Option | Fit | Notes |
|---|---|---|
| **Flutter (recommended)** | ★★★★★ | One codebase; mature plugins: `camera`/`mobile_scanner`, [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition) (Android **and** iOS), `drift`/`sqflite` (SQLite), `pdfrx`/`flutter_pdfview` for PDF, `fl_chart`, `share_plus`, `path_provider`. Custom-rendered UI makes a consistent, polished "incredibly clean" look easier. Thin platform channels (Swift/Kotlin) reach VisionKit, Foundation Models, and ML Kit GenAI when needed. A public [offline Flutter receipt-OCR proof of concept already exists](https://github.com/it2kvku/pocketreceipt-ocr-expense-tracker) following exactly this stack (camera → ML Kit → heuristic parser → SQLite → charts). |
| React Native / Expo | ★★★★ | `expo-camera` or `react-native-vision-camera`, [`@react-native-ml-kit/text-recognition`](https://www.npmjs.com/package/@react-native-ml-kit/text-recognition) with an Expo config plugin, `react-native-pdf`, MMKV/SQLite. Slightly more glue for scanner quality and native AI hooks. |
| Native pair (Swift + Kotlin) | ★★★ | Best scanner polish, 2× effort. Only worth it if Flutter's camera gaps bite hard. |

[2026 framework comparisons](https://codeminer.co/blog/react-native-vs-flutter-2026) consistently flag "advanced camera processing" as the area where cross-platform frameworks still need native escape hatches — which is fine here, because the escape hatches (VisionKit, ML Kit GenAI, Foundation Models) are small, well-documented surfaces.

### 2.2 Text extraction (OCR) — ✅ fully on-device, both platforms

**Tiered extraction architecture is the key design decision.** No cloud OCR is needed:

1. **Classic OCR (baseline, all devices):**
   - **Android:** [Google ML Kit on-device text recognition](https://softwarehouse.au/blog/harnessing-ml-kit-for-fast-accurate-on-device-text-recognition/) — free, offline, Latin scripts out of the box, bundled model only a few MB.
   - **iOS:** ML Kit runs on iOS too (via the Flutter plugin), **or** Apple's [Vision framework `VNRecognizeTextRequest`](https://developer.apple.com/documentation/vision/recognizing-text-in-images) with `.accurate` recognition level.
2. **Heuristic parser (all devices):** regex/heuristics over OCR text — `TOTAL`/`SUBTOTAL` anchors, date patterns, currency symbols, top line = merchant. This alone is good for ~70–85 % of flat-layout receipts; the review screen catches the rest.
3. **On-device LLM structuring (modern devices only, big 2025–2026 win):**
   - **Android:** [ML Kit GenAI APIs](https://developers.google.com/ml-kit/genai) — [Gemini Nano via the Prompt API](https://developers.google.com/ml-kit/genai/prompt/android) accepts **combined image + text input** and emits **structured output**. Google's own [2026 guidance demonstrates exactly this use case](https://android-developers.googleblog.com/2026/07/android-on-device-inference.html): prompt a receipt image → `{title, amount, category}` into a typed schema. Runs via the AICore system service on supported flagship devices.
   - **iOS:** [Apple's Foundation Models framework (iOS 26)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/) exposes Apple Intelligence's on-device ~3B model to third-party apps — [a few lines of Swift](https://dev.to/arshtechpro/apples-foundation-models-framework-run-ai-on-device-with-just-a-few-lines-of-swift-lbp), and [developers report it reading receipts locally](https://medium.com/macoclock/i-taught-apples-tiny-on-device-ai-to-read-receipts-3ee8952f51e6) alongside VisionKit's scanner.

   ⚠️ **Availability constraint:** Foundation Models requires an Apple-Intelligence-capable iPhone (iPhone 15 Pro and newer) with Apple Intelligence enabled; Gemini Nano/AICore needs supported recent Android flagships. On everything else, tiers 1–2 degrade gracefully. This is a **non-blocking** caveat because the app remains fully functional without LLM structuring.

### 2.3 Camera ingestion — ✅ proven, with platform-specific scanner UI

- **iOS:** [VisionKit's `VNDocumentCameraViewController`](https://medium.com/macoclock/i-taught-apples-tiny-on-device-ai-to-read-receipts-3ee8952f51e6) gives Apple's own first-party scanner — live edge detection, perspective correction, multi-page capture — for ~50 lines of wrapper code. Users already know how to use it (Notes, Files).
- **Android:** ML Kit Document Scanner API or a custom `camera`-plugin viewfinder with quad-detection overlay; the ML Kit text-recognition guide above covers the capture-side best practices (throttling, ROI cropping, model reuse).
- Flutter reaches both via small platform channels, or via existing plugins (`flutter_document_scanner`, `qr_code_scanner`-style wrappers).

### 2.4 Screenshot / gallery import — ✅ with an iOS caveat

- **Android:** Photo Picker or `READ_MEDIA_IMAGES` (user-selected). A convenience feature is possible: on Android you *may* list the user's Screenshots folder and let them bulk-pick recent screenshots.
- **iOS:** The photo picker (`PHPickerViewController`) is the right tool — user selects screenshots/album images; no permission prompt needed. **You cannot auto-watch the camera roll for new screenshots**, and iOS never lets your app read what the user screenshotted without them picking it. → Design an obvious "+ Import from Photos" flow and a **Share Sheet extension** so users can share a screenshot/PDF into the app from Photos, Mail, or Files.
- Both platforms: register the app as a handler for PNG/JPEG/PDF via Share Sheet (iOS `NSExtension` / Android `ACTION_SEND`) and file-open intents.

### 2.5 PDF ingestion — ✅ on-device

- **Text-layer PDFs** (e-receipts, statements): extract text directly with a Dart PDF package — no OCR needed.
- **Scanned/image PDFs:** render each page to an image (`pdfrx`/`flutter_pdfview`/`PDFKit`), then run the same OCR pipeline.
- Multi-page bank statements (one PDF → many transactions) is a natural **v2** feature; MVP = one bill/receipt per import.

### 2.6 Local storage & privacy — ✅ straightforward, this is the app's selling point

- **Database:** SQLite (`drift`) — transactions, merchants, categories, budgets. Store money as **integers (minor units)**, never floats (the reference POC above does the same).
- **Images:** app-private documents directory (`path_provider`); thumbnails for the review grid; delete originals on transaction delete.
- **File access requirements (the "local file access" ask):**
  - Android: use **Storage Access Framework** (`ACTION_OPEN_DOCUMENT`) for picking PDFs/files and `ACTION_CREATE_DOCUMENT` for export — no `MANAGE_EXTERNAL_STORAGE`, which would trigger Play policy scrutiny. No broad media scanning needed.
  - iOS: app sandbox + the **Files app** (document picker / file provider). Optional: `UIDocumentBrowserViewController` interop for import/export.
- **Protection:** enable iOS Data Protection (default file-level encryption); Android keystore-backed encryption for the DB if desired (SQLCipher optional in v1). Local **backup/restore** = encrypted zip of DB + images exported through the share sheet / Files / SAF.
- Store declarations become trivial: the literal **"data is not collected"** form — no ad SDK, no analytics, no collectors of any kind (§3.1).

### 2.7 UI & Help — ✅ standard, but a real workstream

- Design once, adapt per platform: Material 3 on Android, Cupertino-adherent on iOS (or one consistent custom design system); full dark mode; large-tap-target review screen; haptics on save.
- Core screens: Home (month overview + budget rings/bars), Transactions list (search/filter), **Scan flow** (capture → processing → editable review → saved), Transaction detail with receipt image zoom, Add manual, Budgets, Reports (charts), Settings (currency, categories, backup, export), **Help**.
- **Help section:** bundled offline Markdown/HTML articles rendered in-app — per-feature pages + "How scanning works" + OCR-accuracy tips (lighting, flat surface, crop) + FAQ; searchable (local index); contextual "?" icons linking into it; optional first-run coach marks. Keep it a first-class tab/drawer entry, not a buried settings link.
- Accessibility (VoiceOver/TalkBack) from day one — cheap to retrofit into a custom design system only early.

---

## 3. Monetization feasibility

> **Owner amendment (2026-11-02, verbatim):** *"I do not want an in app purchase
> capable of unlock, I want no in app purchases other than the buy me a coffee
> tip option. Paid option will have to be through the app store and a smooth
> upgrade from free to paid without losing data is needed."*
> **Supersedes everywhere in this doc:** the paid tier is a **separate paid
> listing on the app store** (paid app SKU), *not* a Play Billing non-consumable
> unlock inside the free app. The only IAP of any kind is the coffee tip
> (consumable donation, §3.2). The "paid only ever adds" philosophy (§3.4),
> price anchors, and the launch value-add pack (decision 9) all stand — they now
> ship *as* the paid app. Mechanics: `docs/design/e6-monetization.md`.

### 3.1 Ads — dropped entirely (decided 2026-11-01)

- **No ad SDK will ship in any tier.** The contextual-only/unobtrusive ad policy drafted earlier today is superseded and removed from scope: no AdMob, no UMP consent SDK, no ATT, no banner layout, no ad declarations in Data Safety/privacy labels.
- **Why:** the honest revenue model (§3.3 reference table) put this configuration at **$2–22/mo through 10k MAU** — while carrying an ad SDK permanently erodes the exact zero-data promise that differentiates the app. The brand and the effort both beat the pennies.
- **What this buys:** the **absolute** privacy claim — *"your data never leaves this device"* — now holds literally, with only two user-initiated network calls: optional live FX rates (toggleable) and, for paid users, backup to **their own** iCloud/Drive. Play Data Safety becomes the literal *"we collect nothing"* form; Apple privacy labels show no collectors at all.
- **Scope saved:** ~1 week of build (§6) plus permanent consent/SDK maintenance. The ad-scenario table in §3.3 is kept as a reference in case anyone ever reopens this.

### 3.2 "Buy Me a Coffee" tip button — ✅ possible, with store-policy nuance

The honest picture in 2026:

- **How it actually works:** there is no in-app checkout SDK for Buy Me a Coffee; the norm is a button that opens the user's browser to your BMC page (an API exists for supporter data, not for native checkout). The tipping itself always happens on the web.
- **Apple history:** Apple's review has rejected BMC links under guideline 3.1.1 — [one developer's long public battle ended only in May 2025](https://medium.com/@robert-baer/my-ongoing-battle-with-apple-over-a-buy-me-a-coffee-link-is-over-9c158df81c05). **Since May 2025**, Apple updated guidelines 3.1.1/3.1.3 for the U.S. storefront to allow external purchase links/buttons with **no entitlement, no approval, and no commission** ([Forasoft 2026 overview](https://www.forasoft.com/blog/article/how-to-avoid-apple-pay-commission-204), [RevenueCat analysis](https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy)).
- **Google:** on [Oct 29, 2025 Google announced U.S. developers may offer external payments/links](https://technologylaw.fkks.com/post/102lroc/google-allows-external-payments-following-upheld-injunction) following the upheld Epic injunction ([Appcharge summary](https://www.appcharge.com/blog/google-opening-the-gates-external-payment-links-are-coming-to-android-in-the-u-s)).
- **Legal fluidity:** the Supreme Court granted cert on June 30, 2026 on the injunction's scope; briefing runs into fall with a decision expected 2027 — **[for now the status quo holds: U.S. link-outs allowed, no Apple commission](https://technologylaw.fkks.com/post/102mp7y/update-your-app-external-purchase-developments-for-apple-google)** ([2026 cost breakdown](https://tiun.io/blog/ios-external-payments-us-cost-2026)). Outside the U.S., external links are governed differently (EU per-DMA, other regions may require the older entitlement or forbid it) — a shipped app would gate the visible tip button by storefront/region.
- **The safest structural rule** (what keeps donation links approvable in practice on both stores): the tip must be **purely voluntary, grant nothing in-app, and never gate features** — that's the [consistent guidance in developer threads](https://support.google.com/googleplay/android-developer/thread/278263151/inquiry-about-including-donation-links-e-g-buymeacoffee-or-patreon-in-a-free-app-on-google-play?hl=en), and even [into late 2026 some devs still treat it as a review risk](https://www.reddit.com/r/googleplayconsole/comments/1xbfcg7/is_putting_donation_links_or_support_links_inside/). If the button unlocks an "Ad-free" toggle or "Pro" badge, it becomes a digital purchase and **must** route through IAP/Play Billing instead.

**Recommendation (revised 2026-11-01, ads dropped per §3.1):** ship the BMC button as a pure, zero-gating "Support development" link in Settings/Help (gated to U.S./EU storefronts), **plus** a store-native **one-time paid unlock carrying the power-user value-adds** (§3.4) — the free tier is feature-complete. Add optional feature-free "Supporter" IAP tiers as the store-compliant in-app tip channel. The IAP is the dependable revenue channel; the tip jar is the goodwill channel.

### 3.3 Recommended monetization stack

| Channel | Effort | Compliance risk | Revenue profile |
|---|---|---|---|
| One-time paid unlock — power-user value-adds (§3.4); ad-removal moot since ads are dropped (§3.1) | Low–Med | Low | **Primary channel:** ~0.5–2% of installs × $7.99–12.99 |
| "Supporter" feature-free IAP tiers | Low | Low | ~0.2–0.5% of installs, avg $4–6 |
| Buy Me a Coffee link (pure tip, zero gating) | Trivial | Low–Med (storefront-dependent; litigation in flux to 2027) | Occasional goodwill tips |

**Realistic paid revenue (decided model, 2026-11-01):** per **10,000 installs**, a well-positioned privacy-first utility converts ~0.5–2% to the unlock (**$400–2,600**) plus ~0.2–0.5% to supporter tiers (**$80–300**) plus a trickle of BMC tips — plan on **~$50–300 per 1,000 installs, one-time**. Honest ceiling for a solo niche app in year 1: low thousands of dollars. The app's payoff is the craft + a self-funding maintenance budget, not income.

<details><summary>Reference — why the ad route was dropped (scenario model, now superseded by §3.1)</summary>

Market inputs: banners are the cheapest format at **~$0.50–$1.50 eCPM** blended ([2026 benchmarks](https://www.choicely.com/blog/in-app-ad-revenue-how-to-forecast-and-maximize-your-apps-return)); **non-personalized ads pay 60–80% less** than personalized ([AdMob eCPM benchmarks 2026](https://www.revenuelab.fyi/blog/admob-ecpm-benchmarks-2026)), so contextual-only finance-app banners land around **$0.20–$0.80 net-of-geo blended eCPM**; Google's take leaves developers roughly **60–80%** of gross ([rev-share overview](https://www.metacto.com/blogs/admob-cost-guide-integration-setup-and-maintenance-expenses)) — model at 65%. App-specific drags: a budgeting app is *low-engagement* (users check a few times a month, not hourly), one Home banner ≈ 1–2 impressions per visit ⇒ **~10 impressions/user/month**, and EEA users who decline consent see no ads (−~15% coverage).

| Scale (MAU) | Impressions/mo | Gross @ $0.40 eCPM | **Net/mo (65%)** | Range |
|---|---|---|---|---|
| 1,000 (realistic year-1 organic) | ~8,500 | ~$3 | **~$2** | $1–6 |
| 10,000 (niche success) | ~85,000 | ~$34 | **~$22** | $11–44 |
| 100,000 (outlier hit) | ~850,000 | ~$340 | **~$220** | $110–440 |

Readings: **$500/mo needs ~150–200k MAU** under this exact configuration; one paid unlock sale ≈ 3 months of ads from 1,000 MAU; the ad layer's build + consent/Data-Safety maintenance (~1 week of §6 effort, forever-after) costs more than it earns below five-digit MAU. **Conclusion at the time — later made moot by dropping ads entirely (§3.1): the unlock + supporter tiers were always going to be the business.**

</details>

### 3.4 Free vs. Paid boundary (no ads, revised 2026-11-01)

**Decisions: the free version is feature-complete; the app carries no ads (§3.1).** Paid = pure **value-add improvements** — depth, convenience, and supporter goodwill. With no ad-removal hook, the unlock must justify itself with demonstrable value, so the menu below is built so buyers clearly feel they received *more*, while anyone who never pays still runs their entire household financially on the free tier. Governing rule, promised in Help and the store listing: **paid only ever adds — it never walls off budgeting essentials or the user's own data.**

**Free tier — the complete budgeting app:**

- Unlimited transactions, scans, and receipt images; all capture channels (camera, photos/screenshot import, share-sheet, PDF)
- **Full budget engine:** monthly + weekly/yearly periods, rollover envelopes, scheduled/recurring bills with local reminders, savings goals
- **Statement import (CSV + OFX)** with mapping profiles and dedupe — free in v1 (reverses the earlier "Pro candidate" positioning)
- Standard reports: month/year views, category & merchant breakdowns, budget-vs-actual, simple projections
- CSV **export**, encrypted local backup/restore, merchant rename/merge (data access & hygiene are never paid)
- Themes/dark mode, per-device base currency + multi-currency, full Help section

**Paid unlock — value-add improvements (final set to pick):**

| Candidate | Value lever | Notes |
|---|---|---|
| **Automatic off-device backup to the user's own cloud** (iCloud Drive / Google Drive / WebDAV) | Safety + convenience | **Flagship.** Scheduled, versioned, zero company servers — the file lives in *their* storage, so the zero-data promise stands. Free tier keeps full manual export + local restore, so free users are never data-risked |
| **Scan queue (batch import)** | Time | 20 receipts arrive as one review queue — still one-by-one review per receipt (decision #5); lands with landlords, freelancers, side-hustlers |
| Home-screen & lock-screen **widgets** (spend-this-month, envelope left, quick-scan) | Visibility | Cheap, high perceived value, and it advertises the app on their wallpaper |
| **Advanced analytics pack:** year-over-year & custom-range comparisons, cash-flow projection detail, recurring-charge detector, multi-sheet PDF/Excel report exports | Depth | CSV export stays free — these are *nicer*, not necessary |
| Tags & custom fields, advanced search operators, bulk edit, duplicate finder | Organization | The classic power-user ask; basic rename/merge stays free |
| Multi-profile / shared-household modes (on-device) | Scope | Couples, personal+business separation; clearly "more," not "less" |
| Extra themes, accent colors, app icons | Expression | Cheap to ship; pairs naturally with widgets |
| v2 line-item analytics — "paid gets it first" | Future | Forward-looking perk now that the schema is reserved (§4.2) |

**Suggested v1 paid bundle:** off-device backup + widgets + analytics pack — three different felt-value levers (safety / visibility / depth) so nearly every buyer finds *their* reason. Rotate in the rest by demand. **In-app pitch matters more now:** with no ad-removal story, the paywall page should *demo* the value (interactive previews of widgets/reports beat greyed-out locks).

**Still optional:** feature-free "Supporter" IAP tiers ($2.99/$6.99/$14.99) alongside the zero-gating BMC link (§3.2) — the compliant in-app tip channel.

**Pricing models:**

| Model | Price guidance | Verdict |
|---|---|---|
| **One-time unlock (non-consumable): the power-user pack** (§3.4) | **$7.99–$12.99** — buyers pay for genuine added value (own-cloud backup, widgets, analytics), not to buy the app back; still cheap next to YNAB/EveryDollar *annual* fees | **Recommended.** Single StoreKit/Play Billing product, restorable from purchase history, no backend; price experiments free via consoles |
| Subscription | $9.99–19.99/yr | Misfits the offline ethos; reserve *only* for hypothetical future sync/cloud |
| "Supporter" feature-free tiers | $2.99–$14.99 | Optional companion, never the only path |

**Guardrails:** Paid features must pass the *"more, not less"* test — someone who never pays must be able to budget a household completely. This positioning is a review-and-reputation asset (privacy-first audiences reward it); revoking anything that was once free is the fastest way to lose it.

**Mechanics notes:** non-consumables must offer restore-purchase; iOS Family Sharing is an optional toggle; both consoles support price experiments with zero code changes.

---

## 4. Requirements list

### 4.1 Functional (MVP)

1. Manual transaction entry (amount, date, merchant, category, account, note, photo attach).
2. Camera scan → document edge detection/crop → OCR → field extraction → **editable review** → save with attached image.
3. Import from Photos/screenshot picker; Share-sheet/file-open intake for images and PDFs.
4. PDF import: text-layer extraction or page-render OCR.
5. On-device AI structuring where hardware supports it (Gemini Nano / Apple Foundation Models), heuristic fallback elsewhere.
6. Budgets: monthly category budgets, overall monthly target, progress indicators.
7. Reports: month view, category breakdown, merchant autocomplete stats, simple charts.
8. Data management: CSV export, encrypted local backup & restore via Files/SAF/share sheet.
9. **Bank-statement import (added to v1 per decisions):** CSV with a user-guided column-mapping step (date/description/amount columns vary per bank; saved per-bank profiles) and **OFX** (standardized XML — direct parse). Import preview, conservative duplicate detection (same account/date/amount), bulk commit into a chosen account.
10. Help section: searchable offline articles covering every screen and the scan pipeline, FAQ, scan-quality tips, statement-import guide.
11. Settings: currency & locale, categories editor, backup/restore (+ paid own-cloud backup destination), paid unlock & restore-purchases, support/tip link, privacy policy.

### 4.2 Non-functional

- Zero account creation, zero telemetry, **zero ad SDKs**; everything works airplane-mode — the only network touches are optional FX-rate lookups and paid backup to the user's own cloud.
- OCR → reviewable result target: < 3 s on mid-range devices.
- Money as integer minor units; **multi-currency capable schema from day 1 (confirmed: launch is English UI, multi-currency amounts)** — per-transaction currency + optional FX rate, base-currency reporting. **Base currency is set once per device (confirmed 2026-11-01)**: one app-wide setting applied to all reports; per-account bases explicitly deferred unless demand emerges. FX *rates* may be fetched on demand (rate lookup ≠ user data in the cloud), so the offline story degrades gracefully: amounts still store, conversions just show unsynced rates.
- **Schema must reserve forward-compatibility:** `line_items` table and per-item fields defined now (populated later in v2); statement-import rows share the transactions table with a `source` discriminator (manual / scan / statement).
- Accessibility, dark mode, localization scaffold (launch is English-only, but OCR scripts and receipt formats vary by locale — keep the heuristic parser locale-aware internally so locales can ship without refactors).
- Min OS: iOS 16+ (Foundation Models feature-detected on 26+), Android 8+ (Gemini Nano feature-detected).

### 4.3 Accounts & compliance paperwork

- Apple Developer $99/yr; Google Play $25 one-time; Buy Me a Coffee account (PayPal/Stripe payout — note [BMC's payout/moderation rules](https://help.buymeacoffee.com/en/articles/4539170-frequently-asked-questions)).
- Privacy policy URL; Play Data Safety form; Apple privacy labels (both trivially clean — no collectors); permission purpose strings (camera, photo picker usage descriptions).

### 4.4 Key risks & mitigations

| Risk | Mitigation |
|---|---|
| OCR/extraction errors on crumpled, angled, or foreign receipts | Mandatory editable review screen; on-device LLM tier on modern devices; heuristics tuned per locale; never auto-commit a transaction |
| iOS no auto-screenshot watching | Fast manual Import-from-Photos + Share extension; Android Screenshots-folder quick-pick |
| Gemini Nano / Foundation Models device coverage | Three-tier extraction architecture with graceful degradation |
| Tip-link store-policy flux (SCOTUS case → 2027) | Tip = zero-gating link (or omit); IAP as primary compliant channel; gate tip button per storefront |
| Paid unlock converts too weakly to fund development | Flagship value-adds (own-cloud backup, widgets, analytics) + demo-style paywall + supporter tiers + BMC fallback; scope the app as craft + self-funding maintenance, not income (§3.3) |
| CSV bank-export format variance (v1 import) | User-guided column mapping + saved per-bank profiles; lean on OFX where banks offer it; conservative dedupe so imports never double-post |
| Great guts, frustrating UI → 1-star reviews sink the app | Decision 10: design-first workflow — validated clickable prototype before feature build; usability gates at MVP and release-candidate; §4.5 quality bar as a launch checklist; polish budget inside §6, not a stretch goal |

### 4.5 UI quality bar (binding, decision 10 — *"no matter how good the guts are, a frustrated user is a lost user"*)

**The two make-or-break surfaces:** the **scan review sheet** (correcting OCR must feel like play, not paperwork) and **manual entry** (a custom large-tap numeric pad, date chips "Today/Yesterday", merchant autocomplete — the stock keyboard is not acceptable for money). Users judge the app in seconds; the extraction engine's quality is only ever *felt* through these screens.

**Measurable acceptance targets (launch checklist):**

- New user's first logged transaction in **< 3 minutes**; onboarding optional, no forced tour, app usable immediately.
- Manual expense in **≤ 3 interactions** from Home (pad amount → tap category chip → save), median < 15 s.
- Scan → review → save in **< 30 s median**, OCR-uncertain fields highlighted so fixing is the happy path; every field editable in place.
- **60 fps on mid-range Android**, camera launch < 1 s, skeleton states instead of spinners; zero blocking work on the UI thread (OCR runs in the pipeline worker, §5).
- **Nothing is ever lost:** auto-saved drafts, undo on every destructive action, never-auto-commit scans.
- One-hand/thumb-first layout throughout; dark-mode parity; WCAG AA contrast; Dynamic Type/font scale to ~2×; VoiceOver/TalkBack passes on core flows; haptics on save/correction/error.
- Empty states teach, errors coach (plain language, never raw codes), Help reachable from every screen (§4.1-10).

**Process commitments:**

- **Design-first:** Figma design system + interactive prototype of the core flows validated in small user tests **before** feature build starts (§6 front-loaded line).
- **Usability gates at MVP and release candidate** (5 testers each round); findings that block retention are launch-blocking, not nice-to-have.
- Platform-native feel: Material 3 on Android, Cupertino-adapted idioms on iOS (bottom sheets, large titles) — never generic cross-platform widgets that read "wrong" on either.
- No telemetry to measure UX post-launch (zero-data stance, §3.1), so quality must be earned **pre-release** by the process above; store reviews and beta feedback are the only instruments — respect them accordingly.

---

## 5. Suggested architecture (build phase, later)

- **Flutter** monorepo; Riverpod state; `drift` (SQLite) + integer minor units.
- Pipeline as an async worker: image bytes → EXIF-aware normalize/crop (isolate) → OCR (ML Kit plugin / Vision) → heuristic parser → optional LLM structuring via platform channels (Swift: VisionKit + Foundation Models; Kotlin: ML Kit GenAI Prompt + Structured Output) → review UI → commit; images written to private dir only after user confirms.
- Help = bundled markdown + lightweight renderer with a local search index.
- CI builds for both stores; fastlane for submission.
- UI layer: a Figma-driven design system implemented once (design tokens → theme), with the custom numeric pad and the scan review sheet as flagship, test-first components (decision 10, §4.5).

## 6. Rough effort estimate (solo experienced dev)

| Milestone | Scope | Time |
|---|---|---|
| **Design (front-loaded, decision 10)** | Figma design system + interactive prototype of core flows (scan review, manual entry, budgets, reports), small-user validated before feature build; motion & accessibility specs | ~2–3 weeks |
| MVP | Manual entry + camera/PDF scan pipeline + review + monthly budgets + basic reports — built from the validated prototype, includes a dedicated polish pass against §4.5 | ~8–10 weeks |
| v1.0 | **Full free-tier budget engine (recurring bills w/ local reminders, rollover, goals, weekly/yearly periods)** and **standard analytics** — free in v1 per §3.4; **CSV/OFX statement import (mapping UI + dedupe)**; LLM-structuring tiers; Help section; local backup/export; **paid pack (locked, decision 9):** own-cloud backup (iCloud/Drive/WebDAV) + widgets + analytics pack + unlock IAP; tip link; RC usability gate + store submission | +10–13 weeks |
| **iOS activation (conditional — decision 11)** | The heavy iOS-only phase, run when Android proves traction: VisionKit scanner & share-extension polish, §4.5 iOS/Cupertino pass + accessibility matrix, TestFlight beta round, perf profiling, Foundation Models device validation, App Store submission | +3–5 weeks *at trigger* |

**Total v1.0: ~20–26 weeks** solo — statement import +1–2 wks and the feature-complete free tier (decision 7) +1–2 wks vs. the pre-decision estimate; the paid pack adds ~2–3 wks, dropping the ad layer gives ~1 wk back (decisions 4 & 7); front-loaded design + explicit polish/usability gates add ~4–5 wks (decision 10). Alternative: launch v1.0 without the paid pack and ship it as a fast-follow v1.0.1 to de-risk the date. **Phasing (decision 11):** the total above ends at the **Android** launch; iOS is *built* throughout (shared codebase, thin platform channels per §5) but its heavy testing/launch phase is deferred to the traction trigger — budget the +3–5 wk activation then, not now.

### 6.1 Where testing runs (environment audit, verified 2026-11-01)

Audited the current dev sandbox (Linux x86_64 Docker container): **Android emulators can't run here** — `/dev/kvm` is not passed into the container, and unaccelerated emulation is unusable; **iOS simulators never run here** — they require macOS/Xcode, and `flutter build ios` itself is macOS-only. Flutter/Android SDK downloads *are* reachable (egress verified), so the sandbox is still a solid **logic & widget tier**:

| Tier | Where it runs | Covers |
|---|---|---|
| Unit (pure Dart) | **this sandbox** + any CI | money math (minor units), FX, heuristic TOTAL/date parsers, dedupe, drift/SQL queries, statement-import mapping profiles — the app's highest-risk correctness surface, fully headless |
| Widget + golden | **this sandbox** + any CI (`flutter test`, headless) | §4.5 acceptance UI: review-sheet interactions, numeric pad, empty/error states, dark-mode & font-scale snapshot goldens |
| APK build + integration code | **this sandbox** (JDK + Android SDK install; egress confirmed) | release builds, R8/size checks; integration_test code compiles but needs a device to execute |
| Android emulator (`integration_test`/`flutter drive`) | **KVM-enabled runner** — the self-hosted GitLab runner once `/dev/kvm` is passed through (below), or a local desktop | E2E flows, permissions, share-sheet, SAF backup — *not* on-device AI (Gemini Nano absent from emulator images) |
| iOS simulator | **Any macOS box** — Xcode Cloud (bundled 25 h/mo) or rented Apple-silicon, wired to GitLab CI via a macOS runner or triggered as an external job | E2E + XCTest/VisionKit glue; `flutter build ipa` is a hard macOS requirement |
| Real devices | TestFlight / Play internal testing; Firebase Test Lab for Android matrix | **Tier-3 LLM structuring (both platforms), camera OCR quality, §4.5 usability gates** — by nature device-bound |

Net: this environment carries the unit/widget tiers and Android builds; CI supplies both emulators/simulators; only physical devices can certify the on-device AI and the §4.5 usability gates.

**CI emulator specifics:** the emulator job is **headless by default** — same AVD, window disabled (`-no-window -no-boot-anim -no-audio -gpu swift_shader_indirect`). `integration_test`/`flutter drive` drive the device over adb with no display, and failures ship as screenshot/screen-record artifacts. Two gotchas: KVM perms need the runner user in the `kvm` group (udev rule) **and** `/dev/kvm` visible inside the job's container (`devices = ["/dev/kvm"]` in `config.toml`), and **x86_64 system images only** — ARM64 runners don't expose `/dev/kvm`. Headless also works without KVM, just unusably slowly — acceleration, not the window, is what determines boot time (why this sandbox is still a no).

**Runner status (probe verified 2026-11-02, pipeline #8):** the GitLab instance has one shared runner (`SteinerRunner`) with a **Docker executor**: jobs run in `alpine` containers on a QEMU VM — 8 vCPU, 15 GiB RAM, ~62 GB disk, registry egress confirmed. **`/dev/kvm` is not exposed to job containers**, so the emulator tier is blocked on that single `config.toml` passthrough (or a second shell-executor/KVM runner); until then CI covers analyze/unit/widget + APK builds, which matches decision 11's deferral of instrumented suites anyway. Job images are pinned per job (`dart:stable` for pure-Dart packages; Flutter+Android SDK image once `app/` lands).

**Runner fleet (2026-11-03, supersedes the paragraph above):** the instance now carries **two** runners. **`SteinerRunner`** (id 1) is the Proxmox VM (`gitlabrunner`, Ubuntu 26.04, 12 vCPU / 32 GiB, docker executor, virtio-balloon pinned off — the page-in killer of pipeline 78 is gone; survived a full Gradle build at 393 s afterward). It owns the baked `localbudget-e2e:latest` image (built from repo `docker/e2e-android`; `pull_policy = if-not-present` reads it straight from the host store) that `e2e-android` and `package-apk` run in. **`SteinerRunner2`** (id 2, accepts untagged jobs) is the second docker-executor box added for parallelism. Early jobs flapped between boxes "randomly" because it had first been registered with the *first* runner's token — one runner record answering from two hosts, so image-bearing jobs landed on a host without the image. After re-registration each machine keeps its own tag; every current job stays pinned to `SteinerRunner` until `localbudget-e2e:latest` is baked on the second box too, at which point dart-test jobs can be load-shared. `runner-probe` / `runner-probe-r2` (manual, same script) identity-check each box after any restart or re-registration.

**Self-hosted runner plan (2026-11-01):** a **Ryzen 5 5560U mini PC** (Zen 3, x86_64 w/ AMD-V, 6C/12T) running Linux natively solves the KVM problem by owning the hypervisor — the headless Android-emulator tier plus all unit/widget/APK-build jobs run there for **zero hosted minutes**, leaving only the (unavoidable) macOS jobs on Apple's or a rental's meters. **Decision 11 keeps that meter near-zero until iOS activation:** a path-filtered `flutter build ipa` whenever `ios/` or a platform channel changes, plus one scheduled weekly headless-simulator smoke run of the critical path (scan → review → save → budget). That's the whole trick of park-then-activate: enough macOS time to *prove iOS hasn't rotted*, none spent polishing a platform that isn't selling yet. Sizing: ≥16 GB RAM (emulator at 8 GB + Gradle/Flutter), ~100 GB free NVMe (SDK + x86_64 system images + caches), runner user in the `kvm` group. Self-hosted-runner hygiene: bind the runner to a restricted runner group that only trusted triggers may target (never run untrusted PR code on it), keep it an isolated box/container, and store no long-lived secrets on it. **What it still cannot do:** build or simulate iOS — macOS-only tooling and Apple's EULA put that on GitHub-hosted macOS runners or a real Mac. **iOS without owning a Mac (verified 2026-11-01):** (1) **Xcode Cloud** — 25 compute hours/month are bundled with the $99 developer membership ([Apple](https://developer.apple.com/xcode-cloud/get-started/)) — builds, simulator tests, TestFlight distribution at no extra cost; (2) **rented Apple-silicon CI** — GitHub-hosted macOS minutes ([runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)), Flutter-native Codemagic, Bitrise, or third-party M4 runner pools — runs `flutter build ipa` + headless-simulator `integration_test` + App Store Connect upload; (3) **interactive cloud Macs** (Scaleway, MacStadium, MacinCloud; AWS EC2 Mac bills a 24-h minimum) when the Xcode IDE itself is needed; (4) **real-iPhone device clouds** ([AWS Device Farm](https://aws.amazon.com/device-farm/), [BrowserStack](https://www.browserstack.com/real-device-cloud)) for XCUITest sweeps and device-matrix crash triage — though camera injection is awkward, so the scan pipeline still wants a phone in hand. EULA: macOS on non-Apple hardware is not permitted, so "no Mac" always means *rented* Mac hardware. TestFlight beta testers need no Mac at all — only the build/upload step does, and that lives in CI. Endgame math: if rented macOS minutes ever exceed ~$350/yr, a used Mac mini M1 pays for itself — but nothing in the launch plan requires owning one. Side benefit: the same box can serve a LAN **WebDAV** endpoint as a free test target for the paid own-cloud backup feature.

---

## 7. Product decisions (settled 2026-11-01)

| # | Question | Decision | Consequence in this doc |
|---|---|---|---|
| 1 | Locale/currency at launch | **English UI, multi-currency amounts** | Integer-minor-units + per-transaction currency/FX schema; locale-aware parser kept internally for future locales |
| 2 | Extraction depth | **Header-level v1; line items in v2** | `line_items` table reserved in schema now; scan pipeline extracts merchant/date/total/category only |
| 3 | Statement import | **CSV + OFX in v1** | Added to requirements §4.1-9; +1–2 weeks; mapping UI + saved per-bank profiles + conservative dedupe; **free tier** (reclassified per §3.4) |
| 4 | Ads | **Dropped entirely — no ad SDK in any tier** (supersedes "undecided") | §3.1 records the drop; all ad scope removed (no AdMob/UMP/ATT/banner work/declarations); unlock sells value-adds only; literal "data is not collected" store forms |
| 5 | Batch scanning | **Single receipt per import** | One capture → one review → one transaction; multi-page capture (if used) treated as one document |
| 6 | Base-currency UX | **Per device** | One app-wide base currency setting; per-account bases deferred (see §4.2) |
| 7 | Monetization philosophy | **Feature-complete free tier; paid = pure value-add improvements** (no ad-removal hook) | §3.4 rebuilt: full budget engine, statement import, standard reports, all data access free; flagship paid value-adds = own-cloud backup + widgets + analytics pack; one-time unlock **$7.99–$12.99** |
| 8 | Data policy | **Zero collection, zero sharing — now absolute** (the contextual-only ad policy is superseded by decision 4) | Public promise can be stated literally: *"your data never leaves your device"*; only user-initiated FX lookups / own-cloud backup touch the network |
| 9 | Launch paid pack | **Own-cloud backup + widgets + advanced analytics pack** | §3.4 bundle locked; scan queue, tags/bulk tools, multi-profile, extra themes become demand-driven fast-follows |
| 10 | UI quality | **Design-first, binding quality bar — "how good the guts are" is worthless if the user is frustrated** | New §4.5 acceptance targets + usability gates at MVP & RC; §6 adds ~2–3 wks front-loaded design + explicit polish budget (total now ~20–26 wks) |
| 11 | Launch phasing | **Build for both platforms from day 1; defer *heavy iOS testing & launch* until Android proves the app has legs** | iOS kept continuously buildable + weekly simulator smoke (§6.1); activation phase §6 +3–5 wks at trigger; TestFlight/device-farm spend starts only then |
| 12 | Paid delivery mechanism | **Separate paid app on the store — no unlock IAP; coffee tip is the only IAP; free→paid upgrade must migrate data smoothly** (owner amendment 2026-11-02, §3 header) | Two flavors one codebase (`free` complete / `pro` = free + decision-9 pack); same signing key; data hand-off via signature-level ContentProvider transfer or the existing encrypted-backup path; `docs/design/e6-monetization.md` is the mechanic contract |
| 13 | Document import (owner request 2026-11-04) | **Bills and bank statements import from image / PDF / photo** — routed through the two existing machines, no new pipeline | E11 (`docs/design/e11-document-import.md`): classified on-device (`DocType` heuristics exist), statements → `CsvPreview` rows on the E5 wizard Preview (bulk, dedupe, `statementImport`), bills → `BillPrefill` into the E3 editor (1:1, decision 5 respected); parsing stays pure Dart — the LLM tiers never produce statement rows; multi-page text **is** v1 here, superseding the §6 "multi-page statements = v2" note (that line predates decision 5's review-first pattern making bulk rows safe) |

Remaining open questions (non-blocking, resolve during design phase):

1. **Fast-follow ordering** for the remaining paid-menu rows (§3.4): scan queue, tags/custom fields + bulk tools, multi-profile, extra themes/icons, v2 line-items "paid gets it first" — sequence by beta feedback after launch.
2. **Category taxonomy**: ship a default category set (groceries, dining, transport, utilities…) — user-extensible; needs naming/copy pass in the Help section.
3. **App name & icon**, store listing copy, privacy policy hosting.
4. **iOS activation trigger (decision 11):** concrete "has legs" thresholds (e.g. installs + D30 retention + first unlock sales) **plus a hard clock cap** (e.g. decide by month 6 regardless) so the deferral can't drift into never.
