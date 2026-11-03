# E6 Design Spec — Monetization (Pro unlock · supporter tiers · Buy Me a Coffee)

**Plan refs:** issue #7 · decisions 4 (no ads, ever), 7 (feature-complete free tier),
8 (zero data collection — absolute), 9 (launch paid pack = own-cloud backup +
widgets + analytics pack). **Guardrail (binding, §3.4):** *paid only ever adds —
it never walls off budgeting essentials or the user's own data.* Free users keep
every existing feature; this epic adds a store product surface, nothing is
removed from free.

Deviation rule applies: this doc is the contract; changes here first, code second.

## 1. Where it lives

```
packages/billing/            NEW pure-Dart package (no Flutter, no plugin deps)
  lib/src/models.dart        BillingProduct, PurchaseInfo, ProStatus, PurchaseEvent
  lib/src/gateway.dart       abstract BillingGateway  (the seam)
  lib/src/fake_gateway.dart  scripted fake for tests/dev
  lib/src/pro_service.dart   ProService — entitlement state machine
  lib/src/support.dart       SupportPolicy (region gate) + SupportLinks
app/lib/features/pro/
  in_app_purchase_gateway.dart  adapter: in_app_purchase (Android) → BillingGateway
  paywall_screen.dart        full-page pitch (Navigator.push, like import sheets)
  manage rows                Pro section added inside ManageScreen
app/lib/features/manage/io.dart  Io gains `openUrl` (browser link-out)
```

`LocalBudgetApp` gains an optional `pro` (ProService?) hand-down exactly like
`fx`/`io`/`restore` (main.dart → LedgerScreen → ManageScreen):
**null ⇒ the Pro section renders one explanatory row** ("Monetization is not
wired in this build"). Legacy widget tests and all 44 existing goldens are
therefore untouched; `main()` wires the real adapter on Android, null elsewhere
(iOS keeps building per decision 11; StoreKit lands with E10).

**No schema migration.** Entitlement persistence is the existing `Settings` kv
table (`LedgerRepository.setSetting/setting`, same pattern as `live_fx_rates`).
New keys — defined as constants in `ProService`, injected via a tiny `SettingsKv`
interface (`get(key)/set(key,value)`) so the billing package stays dependency-free:

| key | value | meaning |
|---|---|---|
| `pro_unlocked` | `'on'` | cached entitlement for offline boots |
| `pro_unlocked_ms` | epoch ms | when it was first seen (debug/help only) |
| `supporters_acked` | csv of product ids | supporter thank-you badge state |

## 2. Products & pricing

Play Console product ids are permanent; choose once:

| id | type | launch price | grants |
|---|---|---|---|
| `lb_unlock_pro` | non-consumable | **$7.99** (decision 7 anchor; console price experiments are the tuning knob — no code changes) | the E7 launch trio: own-cloud backup, widgets, analytics pack |
| `lb_supporter_1` | non-consumable | $2.99 | nothing — thank-you badge only |
| `lb_supporter_2` | non-consumable | $6.99 | nothing |
| `lb_supporter_3` | non-consumable | $14.99 | nothing |

Discrepancy note: issue #7 body lists supporter tiers as $2.99/$4.99/$9.99; the
binding plan (§3.4 "Still optional") says $2.99/$6.99/$14.99. **The plan wins**;
closing comment on #7 records the resolution. Console ops (create products,
price anchor, A/B experiment scaffold) are an **E9 pre-submission checklist item**,
tracked in the spec's §9 — nothing here needs the Console to exist to build.

Restore semantics follow store rules: non-consumables must restore from purchase
history (`queryPurchasesAsync`), works **offline** once cached, no backend, no
account (decision 8). Validation is billing-client-only; a rooted device can
forge the local flag — accepted by design (zero-server promise; we sell value,
not DRM). This trade is stated here so no one "fixes" it later with a server.

## 3. The gateway seam

```dart
abstract class BillingGateway {
  Future<void> connect();
  Future<List<BillingProduct>> products(List<String> ids);
  Future<void> buy(String productId);
  Future<List<PurchaseInfo>> pastPurchases();      // non-consumable only
  Future<void> ack(PurchaseInfo purchase);
  Stream<PurchaseEvent> get events;                // pending|purchased|error|canceled
  Future<String?> accountCountry();                // Play billing config, null=unknown
  Future<void> close();
}
```

Domain models carry `productId`, `purchaseToken`, `pending`, `status`. The
`in_app_purchase` plugin is referenced **only** by the app-layer adapter
(`in_app_purchase_gateway.dart`), which maps plugin enums → `PurchaseEvent` and
acks after the ProService has persisted state. An unacknowledged purchase that
dies mid-flow reappears in `pastPurchases()` next launch — the flow is
crash-safe by construction; no explicit resume logic.

`FakeBillingGateway` (ships in the package, used by all tests; selectable in dev
builds with `--dart-define=FAKE_BILLING=true`) is scriptable: canned catalog,
deterministic success/failure/pending→purchased sequences, fake country. The
sideloaded debug build without a Play listing hits the *products-unavailable*
state (§6) — the paywall must still render fully; nothing is broken, just
unbuyable. This is explicitly verified.

## 4. ProService — state machine

`ProStatus ∈ {unknown, locked, unlocked}`; `Stream<ProStatus> status` (broadcast).

Boot (`ProService.bootstrap()` — call at startup, off the critical path like the
E5 integrity probe): connect (best-effort, 5 s deadline) → `pastPurchases()`.
- query **succeeds** and contains `lb_unlock_pro` ⇒ `unlocked` (write cache keys).
- query **succeeds**, product absent ⇒ `locked`, cache *cleared* — this is how a
  refund is honored without a backend.
- connect/query **fails** (offline, no Play) ⇒ `unlocked` iff cache says so, else
  `locked`. The app never blocks on billing; worst case the row reads "locked"
  and Restore fixes it in one tap once online.

`buy(productId)`: gate single-flight; drive from `events`; on purchased → persist
(`pro_unlocked` or append `supporters_acked`) → `ack` → emit. Errors surface as
the mapped message from §6.
`restore()` = re-run the boot query with a user-visible result
("Pro restored" / "No purchase found for this Google account").

**E7 consumption contract:** `bool enabled(ProGate gate)` over the same stream,
`enum ProGate { ownCloudBackup, widgets, analyticsPack }`. Free features never
call it. E6 ships service + tests; E7 attaches gates.

## 5. Paywall page

One Navigator-pushed page (no route table exists; same pattern as the import
sheet stack). §4.5 rules apply: it *demos* value — no greyed-out lock teasers.
Structure, top→bottom, one scroll:

1. **Headline** — "Pro. One purchase, yours forever." + price chip from the
   store catalog (`$7.99` localized by Play; fallback text when catalog empty).
2. **Three demo cards** — the launch trio rendered as honest mini-previews:
   own-cloud backup (animated file-to-cloud motif over the user's *own* words
   "your Drive, your WebDAV"), widgets (rendered mock tiles using the app's
   real tile design language), analytics pack (a mini YoY sparkline). Copy
   states plainly: "coming with the Pro pack" until E7 ships each — the app
   never shows a fake-enabled feature as live.
3. **Buy** button (primary; disabled with reason when catalog unavailable) +
   **Restore purchases** text button.
4. **Promise** line, verbatim from §3.4: "The free app stays complete. Pro only
   adds."
5. **Support section** (region-gated, §7): "Say thanks ☕" → BMC browser
   link-out (`Io.openUrl`; grants nothing — store-rule compliant) and the
   supporter tier chips (own-row thank-you badge when owned).

States: loading (skeleton), ready, products-unavailable, purchasing (button
spinner; re-tap ignored), failed (mapped snackbar §6), unlocked (card 1 swaps to
"Pro unlocked ✓ · Manage" showing purchase era from `pro_unlocked_ms`, buy
button gone, restore stays). Refund → next boot flips back to locked silently.

**BMC URL** is a constant in `SupportLinks` (`https://buymeacoffee.com/…`); the
handle is decided with app naming in E8 (open question #3) — a placeholder
`TODO(store)` comment blocks merge of *E8's* checklist, not this epic; E6 ships
with the link pointing at a placeholder page and E8 finalizes it.

## 6. Error copy map (snackbars; §4.5: explain, never stack-trace)

| store condition | message |
|---|---|
| user canceled | *none* (silent) |
| network / service down | "Can't reach the store right now. Try again later." |
| item not available (sideload/no listing) | "This item isn't available in your store yet." |
| purchase pending (family review, deferred) | "Purchase pending — Pro unlocks as soon as it completes." |
| billing unsupported on device | Pro row reads "Not available on this device." |
| restore finds nothing | "No purchase found for this Google account." |

## 7. Region gate for support link-outs

Feasibility §3: U.S. link-outs are permitted status-quo; other regions differ.
`SupportPolicy.visible(countryCode)` → true iff `'US'`; unknown/null → hidden in
release, shown in debug (development affordance only). Country comes from the
Play billing config (`accountCountry()`); billing absent → null → hidden
(release). One allowlist constant; broadening it later (EU/DMA) is a one-line
spec edit + code follow, deliberately not preemptive.

## 8. Test & CI surface

- **packages/billing** (pure Dart, `flutter test`): boot matrix (success×{owns,
  absent} / offline×{cache on,off}), refund-clears-cache, buy happy path incl.
  ack ordering (persist→ack), pending→purchased, single-flight, supporter acks,
  ProGate, SupportPolicy matrix. `billing-test` CI job (dart:stable) added.
- **app widget tests**: paywall every §5 state × light; Pro section rows with
  `pro` null (unchanged legacy behavior), locked, unlocked; BMC row region
  gate on/off; restore snackbar paths via `FakeBillingGateway`.
- **goldens** (CI regen flow, names per convention): `paywall_locked_{light,dark}`,
  `paywall_unlocked_{light,dark}`, `paywall_unavailable_light`,
  `manage_pro_locked_{light,dark}`, `manage_pro_unlocked_light` → +7 refs (44→51).
- **e2e**: unchanged; `--dart-define=FAKE_BILLING=true` reserved for a future
  on-device billing-lint pass (E9 perf/audit day).

## 9. Out of scope / ops

E7 (gates + the trio), E8 (help articles incl. billing & "paid only adds"
promise, final BMC handle, store copy), E9 (Play Console: create 4 products,
anchor $7.99, launch price experiment $6.99↔$9.99 after beta per issue #7,
internal track), E10 (StoreKit parity, Family Sharing toggle, revenue-pool
split). Data Safety form: purchases are processed by Google; we continue to
collect nothing — unchanged declaration.
