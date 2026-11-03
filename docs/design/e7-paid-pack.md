# E7 Design Spec — Paid pack: the launch trio

**Scope = issue #8 = decision 9, as amended by decision 12.** Three features
ship *inside the Pro SKU*: own-cloud backup, home-screen widgets, and the
analytics pack. The free app's behavior does not change — not one screen, not
one byte of network. "Paid only ever adds" (decision 7) now literally means
*installing the other app adds these*.

**Checkbox #4 restated.** The issue's plan line predates decision 12 and said
"entitlement gate for all three (restore works offline)". Under decision 12
there is no in-app entitlement to gate on: **the install *is* the entitlement.**
The gate is `FeatureFlags.proTrio` (`app/lib/flavor.dart`) — a compile-time
build fact that provably never touches the network, which satisfies "offline"
in the strongest possible sense. No billing call may ever appear in an E7
code path; the E6 §0 invariant (nothing unlocks anything, test-enforced) is
inherited unchanged and extended by §6's tests.

## 1. Order of work and code placement

| Slice | Ships | Lives in |
|---|---|---|
| E7a analytics pack | first — pure Dart on E4's queries, zero platform surface | `packages/budget` (queries), `app/lib/screens/analytics/` |
| E7b own-cloud backup | second — the flagship, new `packages/data/lib/cloud/` | `packages/data` (transport), `app/lib/screens/cloud/` |
| E7c widgets | third — Android-only platform code | `app/android/.../widgets/`, snapshot contract in `packages/core` |

Each slice lands with its own goldens and both flavor suites green
(free suite must be *byte-identical in behavior* — it gains tests asserting
invisibility, §6).

## 2. E7a — Analytics pack

1. **Custom ranges + YoY.** The E4 report engine gains an explicit-range
   query (`from`, `to`, optional compare-range). UI: range sheet with presets
   (This month / Last month / This year / Last year / Custom) and, when a
   compare range is set, a second translucent series on the trend chart plus
   a delta card (`+12.4% vs Jan 2025`). All math on minor units, E3 rules;
   partial-month compares normalize by day-count and say so on the card.
2. **Recurring-charge detector.** Pure function over transactions: group by
   normalized merchant (§3 E2 normalization), then flag groups with ≥ 3 hits,
   inter-arrival in 27–33 days, amount CoV ≤ 15 %. Output is *suggestions*:
   a "Detected recurring" card list on the analytics screen; one tap converts
   a suggestion into an E3 recurring bill via the existing editor sheet,
   prefilled. Nothing is ever auto-applied. Runs on-device over the local DB;
   the detector is deterministic and golden-tested with a fixture ledger.
3. **PDF + Excel export.** Report export sheet gains, *pro only*: "PDF report"
   (multi-page: summary, monthly tables, category breakdown — `pdf`/`printing`
   packages) and "Excel workbook" (`excel` package, sheets: Summary / Months /
   Categories / Transactions). Free tier keeps CSV forever (feasibility §4.5:
   the pack makes exports *nicer*, not possible). Both write through the
   existing share sheet, never to cloud.
   *Implementation addendum (`implemented`): the entry point is a pro-gated
   "Export report" tile on the analytics screen itself (§2.4 guard). Neither
   package named above ships: `printing` adds a native plugin the byte-share
   flow never needs (`pdf` alone renders to memory), and the pub `excel`
   package is dead — its xml ^5 line cannot coexist with this repo's xml ^6 /
   archive ^4. XLSX instead comes from a minimal hand-rolled OOXML writer in
   `package:data` (inline-string + numeric cells, stored zip), built on the
   `archive` dependency data already has and unit-tested by unzipping its own
   output. `app` pins `archive: 4.6.0` via `dependency_overrides` — `pdf`'s
   declared cap predates the `image` release it resolves; its archive import
   is a web-only shim that never compiles on VM.*
4. **Gate.** Entry points live under the analytics screen's pro-only section;
   routes are wrapped by a guard that renders `SizedBox.shrink()` on free and
   is asserted by widget tests (§6) — not a hidden button, a compiled-off path.

## 3. E7b — Own-cloud backup (flagship)

**Promise:** scheduled, versioned, end-to-end-encrypted `.lzbak` containers
(E5 §format, unchanged — reuse `createBackup`, never a new container) pushed
to storage *the user owns*. Zero company servers (decision 8); the literal
"your data never leaves this device" claim in feasibility §3.1 becomes "…unless
*you* send it to *your* cloud", which the doc already sanctions.

### 3.1 Targets (v1)

| Target | Mechanics | Notes |
|---|---|---|
| **WebDAV** | URL + user + password/app-password; MKCOL the upload folder, PUT objects; PROPFIND Depth:1 to list | HTTPS required; plain-HTTP only allowed when the host is RFC1918/loopback with a visible red-banner warning (the user's own NAS/LAN box is a first-class citizen) |
| **Google Drive** *(sequenced after WebDAV — owner decision 2026-11-03)* | Drive REST v3 with scope `drive.appdata` only — files live in the app's hidden folder, invisible to the user's Drive UI and to every other app | OAuth 2.0 authorization-code + PKCE in a Custom Tab; **no Google SDK dependency**; tokens are stored locally in secure storage and are never sent anywhere but `oauth2.googleapis.com`/`www.googleapis.com`. Needs one external artifact: an "installed app" OAuth **client ID** from the owner's Google Cloud project (not a secret; PKCE so no embedded secret). Until that ID exists the Drive provider stays dark-shipped code, not a UI target; E7 ships on WebDAV alone and the Drive provider lands as a follow-up commit the day the ID arrives |
| **iCloud Drive** | deferred to M4 / E10, per issue | iOS-side mechanics join decision 11's activation |

Multiple destinations per profile are allowed (e.g. NAS + Drive). A
destination = {type, label, endpoint, secret}; secrets live in
`flutter_secure_storage`; deleting a destination scrubs its secret and forgets
nothing else (remote files are the user's to delete).

### 3.2 Versioning and retention

Object name `localbudget-<profileSlug>-<UTC yyyymmdd-hhmm>.lzbak`. Retention
per (profile, destination): keep the newest 12, *and* collapse older ones to
the newest per calendar day; prune runs after a successful upload, never
before. Listing = PROPFIND (WebDAV) / `files.list` on appDataFolder (Drive);
no local manifest, so a fresh install can enumerate versions from the server
alone. Version list UI: date, size, restore button, delete.

### 3.3 Schedule

WorkManager periodic (24 h minimum) with constraints = network available +
battery not-saving; user-toggled per destination ("Back up automatically").
"Back up now" is always available and ignores constraints except connectivity.
Failures: 3 retries with backoff inside the worker, then a quiet badge on
Settings → Paid pack — never a notification unless the user enabled one
(default off, respecting the notification minimalism of E3 reminders).

Enabling the toggle enrols a *backup key* once (passphrase sheet with
confirm) and keeps it in flutter_secure_storage (`cloud-autokey-<id>`) —
the same trust domain already used for the destination secret, which
unattended uploads need anyway. The worker only encrypts fresh snapshots
with that key (E5 containers stay self-describing, so restore is
unchanged); disabling the toggle or removing the destination scrubs it.

### 3.4 Restore

Version list → download to cache → passphrase prompt → the E5 restore flow
(verify container, confirm, swap) unchanged. A cloud restore can *only*
replace local data; it never merges — same confirm-sheet as local restore,
plus a "from <destination>, <date>" header line.

### 3.5 Zero-collection invariants (test-enforced, §6)

Outbound network in E7b is exactly: the user's configured WebDAV host, and
`oauth2.googleapis.com` / `www.googleapis.com` (Drive target). No telemetry,
no crash reporters, no reachability pings (constraint failures are inferred
from WorkManager callbacks). Backup files are encrypted *before* leaving the
device; the passphrase is never stored, never transmitted, and password
managers aside the UI says the recovery math out loud (lost passphrase =
unreadable backups — same truth as E5).

## 4. E7c — Widgets (Android)

1. **Three widgets** (Jetpack Glance, resizeable, API 26+):
   *Spend this month* (total + budget progress + tap→reports),
   *Envelope left* (configured per instance via glance's per-widget prefs at
   pin time; tap→that envelope), *Quick scan* (tap→capture sheet directly;
   the tile that advertises the app on the user's wallpaper, per feasibility).
2. **Snapshot contract, not DB access.** Dart writes
   `filesDir/widget/state.json` — aggregates only (month totals, per-envelope
   remaining, currency, updatedAt) — debounced 2 s after ledger writes and on
   app foreground. Kotlin reads *that file* and nothing else (same isolation
   discipline as the E6 transfer channel; widget code never opens the DB or
   passes through Dart). Schema = a small data class in `packages/core` with
   a Dart↔Kotlin parity test (fixture JSON committed).
3. **Refresh:** after each snapshot write the bridge calls
   `AppWidgetManager.requestUpdateAppWidgets`; plus a low-frequency
   WorkManager tick as fallback (day-rollover correctness without opening
   the app).
4. **Privacy:** the snapshot contains zero transaction rows, zero merchant
   names, zero paths — the widget is aggregates-only *by schema*, and the
   parity fixture test asserts no key outside the allow-list exists.
5. Lock-screen: API 31+ shows configured home/lock widgets — nothing extra
   to build beyond glance's standard configuration flow.

## 5. Surfacing (no nag policy)

Pro app: Settings → **Paid pack** section (backup destinations, widgets
setup guide, analytics export note) + analytics-screen pro section (§2).
Free app shows *nothing trio-related except* one informational line on the
existing Support page ("The paid app adds cloud backup, widgets and advanced
analytics") linking the store listing — no interstitials, no badges, no
feature teasers. Decision 7's "free tier complete" survives literally.

## 6. Tests & gates

- **Flavor gates:** free suite gains route-guard tests — every trio route
  renders empty on free; `grep`-style CI assertion that `lib/screens/cloud/`
  and `lib/screens/analytics/pro/` are imported only behind `FeatureFlags.proTrio`
  guards; detector/export unit tests run under `--dart-define=APP_FLAVOR=pro`.
- **E6 invariant extended:** the billing layer still gains zero new callers;
  no symbol named `unlock` anywhere; new code may not import `iap_gateway`.
- **Unit:** range/YoY math (fixtures incl. partial months, FX periods),
  detector precision/recall on the fixture ledger, retention/prune logic,
  WebDAV client against an in-test `shelf` server (auth, MKCOL 405, PROPFIND
  parse, partial-upload retry), Drive client against a stub REST server
  (PKCE flow, appdata scope, 401 refresh-once).
- **Goldens (pro suite, expected 7–10):** range sheet, compare card, detector
  card list, export sheet (pdf/xlsx visible + CSV still free), cloud settings
  + destination editor (password masked), version list (restore/delete),
  restore-from-cloud confirm, widgets guide page.
- **Integration (VM2 e2e):** one Drive-free, WebDAV-only happy path against
  the LAN NAS endpoint (spec §3.5's own box), guarded by a CI variable; where
  the NAS is absent the test skips with a loud log, never silently passes.
- **Manual:** Flip6 widget matrix (pin/configure/rotate/kill-app refresh) and
  Drive PKCE round-trip — the latter belongs to the Drive follow-up (once the
  client ID ships), not to the E7 gate; recorded in the E7 acceptance
  checklist, done once.

## 7. Explicitly out of scope

iCloud target (M4/E10), iOS widget parity (E10 Cupertino pass), any billing
surface for the trio (decision 12 forbids it, §0), server-side encryption or
de-dup (clients encrypt before upload; servers store opaque blobs), tags /
multi-profile / scan-queue (later epics — §4.2 of feasibility keeps them as
candidate pack contents, E7 ships exactly the decision-9 trio).
