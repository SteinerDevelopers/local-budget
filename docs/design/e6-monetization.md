# E6 Design Spec — Monetization v2 (paid app SKU · coffee tip · data-preserving transfer)

**Supersedes this file's v1 (same day).** Owner amendment, 2026-11-02, verbatim:
*"I do not want an in app purchase capable of unlock, I want no in app purchases
other than the buy me a coffee tip option. Paid option will have to be through
the app store and a smooth upgrade from free to paid without losing data is
needed."* Recorded as decision 12 in `docs/feasibility.md` §7.

**The invariant this epic now enforces: billing state never unlocks anything,
anywhere, ever.** Features are switched by *which app you installed*, never by
a purchase flag. The only IAP in the product is the coffee tip, which grants
nothing but a thank-you. Test-enforced (§8).

Standing decisions survive untouched: no ads (4), free tier feature-complete
(7), zero collection (8), the value-add trio (9), "paid only ever adds" —
the trio now ships *as* the paid app instead of being unlocked inside the free one.

## 1. Two SKUs, one codebase

Android product flavors of `app/`, dimension `tier`:

| | free | pro (paid) |
|---|---|---|
| applicationId | `dev.steiner.local_budget` | `dev.steiner.local_budget.pro` (suffix `.pro`) |
| store price | $0 | price anchor **$7.99** (v1 §2 survives as the *listing* price; console experiments, no code) |
| contents | the complete app today + every "free" feature forever | free + the decision-9 pack (own-cloud backup, widgets, analytics) delivered by E7 |
| manifest | hosts the transfer ContentProvider (§3) | queries + consumes it; no provider |

Dart learns its flavor once: `--dart-define=APP_FLAVOR=pro` (CI sets it per
flavor; unset ⇒ `free`). `AppFlavor` + `FeatureFlags.pro` live in
`app/lib/flavor.dart` — **the only feature-gating mechanism that exists**.
E7's trio reads `FeatureFlags.pro`; it must not read billing (E7 spec amended
accordingly when written). iOS: same flavor pair via schemes xcconfig, StoreKit
work deferred exactly as decision 11 — iOS *paid app* mechanics are an E10 item.

Signing: both flavors are signed with the same key — the transfer (§3) depends
on same-signature identity, and it is the only cross-app relationship allowed.

## 2. Products — tips only

Play Billing remains in the tree for one purpose. Consumables, no entitlement:

| id | price | grants |
|---|---|---|
| `lb_coffee_small` | $2.99 | nothing — thank-you badge + local receipt line |
| `lb_coffee_medium` | $6.99 | nothing |
| `lb_coffee_large` | $14.99 | nothing |

A consumable tip is ack'd immediately on purchase (it is consumed by the act of
thanking); pending tips surface §6 copy and, if they complete later, the
lifetime event listener records the badge. No restore surface is required for
consumables — none is offered. The browser-out **Buy Me a Coffee** link (§5,
`SupportLinks.bmc`) stays as the non-IAP alternative, grants nothing, region-
gated (§7). v1's `lb_unlock_pro` / supporter-nonconsumables are *deleted from
the spec and the code*; nothing named `unlock` may exist (§8).

## 3. Smooth upgrade: free → paid without losing data

The store gives paid→free no upgrade path (different packages), so the app owns
the migration. Both directions of the UX are one tap after install:

**Free app, Settings → "Get Pro"**: explains the trio (demo cards survive from
v1 §5 — honest previews, no greyed locks), deep-links the Play listing
(`market://details?id=dev.steiner.local_budget.pro`, https fallback), shows a
*Copy my data* button that stages the transfer snapshot (see Transfer
mechanics), and — when the Pro package is visible — shows "Pro installed? Open
it and tap *Transfer from free app*." It never moves or deletes anything itself.

**Pro app, first run (and a standing Settings row)**: "Transfer from free app"
appears only when the free app's provider resolves. One tap copies everything
and lands the user in their own ledger.

### Transfer mechanics

- The free app exports a `ContentProvider` (authority
  `dev.steiner.local_budget.transfer`, `permission` = a
  `signature`-protection-level custom permission; declared in the *free*
  flavor's manifest only; Pro declares `<queries>` + uses the permission).
  Same signing key ⇒ instant grant; **no runtime permission dialogs, data
  never leaves the device, no network, no backend** (decision 8 intact).
- Kotlin cannot run the Dart backup pipeline, so the provider never
  *generates* anything: the free app's Dart side **stages a prepared
  snapshot**. `createBackup` (with `transferPassphrase`) is written through a
  MethodChannel to a dedicated file (`<filesDir>/transfer/staged.lzb`) when
  the user taps *Copy my data* on the Get Pro screen, and again opportunistically
  on app pause when anything changed since the last stage. The provider only
  *serves* that file and reports its (size, mtime); the Pro-side channel call
  spools the container to a cache file and hands it to the *existing* E5
  restore path (single confirm, cold restart — restore remains the only
  destructive flow, and on the Pro app the "existing data" it replaces is an
  empty database on first run).
- **Freshness, stated honestly**: transfer copies the *last staged snapshot*,
  which is current the moment the user follows the on-screen steps (stage on
  Get Pro, refresh on pause). Pro shows the snapshot's timestamp before the
  confirm, and the copy instructions say so — no pretend live replication.
- **Transfer passphrase**: `createBackup` demands a passphrase; the transfer
  uses a constant compiled into the app family (`transferPassphrase`,
  `packages/data`). Threat model stated plainly: it is obfuscation, not a
  secret — it defends nothing against a rooted device, and that is *no worse*
  than the free app's own unencrypted-at-rest SQLite. Its job is format
  honesty: one pipeline, one envelope, zero plaintext special-casing.
- Idempotent: transfer can be repeated (Pro re-pulls a newer snapshot any
  time); the free app is never modified — uninstalling Pro loses nothing,
  and the free app keeps working as the complete app it is.
- **Fallback** (provider edge cases, future iOS): the classic route — export
  encrypted backup file in free app (E5), import it in Pro (E5). The spec
  promises *a* path always; the provider is only the smooth one.

## 4. Billing seam (v2) — consumable-only

```dart
abstract class BillingGateway {
  Future<void> connect();
  Future<List<BillingProduct>> products(List<String> ids);
  Future<void> buy(String productId);
  Future<void> ack(PurchaseInfo purchase);
  Stream<PurchaseEvent> get events;      // pending|purchased|canceled|error
  Future<String?> accountCountry();
  Future<void> close();
}
```

`pastPurchases` is gone with the non-consumables. `TipService`
(`packages/billing/lib/src/tip_service.dart`, pure Dart): `catalog()` (the
three ids), `tip(productId)` → `BuyResult` for UI copy, lifetime listener
records completed tips into the `tips_acked` kv (cosmetic receipt),
single-flight guard. `in_app_purchase` types still stop at the app adapter;
`FakeBillingGateway` keeps scriptable events + `productsThrow` for tests/dev.
No ProService, no `ProStatus`, no restore ladder — deleted with v1.

## 5. UI

**Settings rows (Manage screen)** — `pro`-flavor-only rows hidden on free,
support rows on both:
1. "Buy me a coffee ☕" → sheet below. Present in both SKUs (Pro buyers tip too).
2. "Get Pro →" — **free flavor only**; opens the Get Pro page (§3, incl.
   *Copy my data* staging + store deep link). Null-safe
   hand-down like every other service: services absent ⇒ row explains, goldens
   stable.
3. "Transfer from free app" — **pro flavor only**, visible only when the
    provider resolves; shows the staged snapshot's age, then runs §3 with the
    §6 error map.

**Coffee sheet**: headline "Enjoying LocalBudget? Buy me a coffee ☕" + the
honest line "Everything you use today stays free. Tips keep the lights on —
they don't unlock anything." Three price chips from the catalog (fallback
"store unavailable" per §6), tip button (pending spinner), thank-you state
after success ("Thank you! ☕" + badge row of past tips). No purchase ever
changes app behavior — visibly stated.

**Get Pro page** (free flavor): headline "LocalBudget Pro — the same app, plus"
+ trio demo cards (surviving v1 §5) + price chip + store button + "your data
comes along, one tap, stays on your device" + fallback route note. No buy
button exists here — buying happens on the store. (E7 replaces trio cards
"coming" copy with live features inside the Pro SKU.)

## 6. Error copy (tips + transfer)

| condition | message |
|---|---|
| user canceled tip | silent |
| store unreachable | "Can't reach the store right now — try again later." |
| tip item unavailable | "Tipping isn't available in your store yet." |
| pending | "Tip is processing — thank you either way." |
| transfer: free app not found | row hidden (never shown) |
| transfer: provider/refused/IO error | "Couldn't read from the free app. You can still use an exported backup file." |
| transfer: schema too new | existing E5 `BackupSchemaTooNew` copy (free app is older than Pro — free updates fix it) |

## 7. Region gate — unchanged from v1

`SupportPolicy.visible(countryCode, debug)`: link-out row shown for `US`,
hidden for other countries, debug-visible when unknown. Tip **IAP** chips are
not region-gated (IAP is always the compliant path).

## 8. Test & CI surface

- **packages/billing** (pure Dart): tip happy path (buy→purchased→ack→badge),
  pending→late purchased, canceled silent, error pass-through, single-flight,
  catalog filtering, `productsThrow` degradation, SupportPolicy matrix.
  **Invariant test:** the exported catalog contains no product whose id
  contains `unlock`; `TipService` exposes no entitlement getter (compile-time
  by absence — the test pins the catalog).
- **app widget tests**: coffee sheet every §5 state; Get Pro row flavor
  matrix (free shows / pro hides / null explains); transfer row visibility
  matrix; thank-you badge rendering from `FakeBillingGateway`.
- **transfer contract test**: round-trip through a temp dir using the real
  `transferPassphrase` + `createBackup`/restore path (provider plumbing is
  e2e-covered later; the *format* is CI-covered now).
- **goldens**: `coffee_sheet_light/dark`, `coffee_thanks_light`,
  `getpro_page_light/dark`, `manage_support_rows_light/dark` → +7 refs
  (44→51). Existing goldens untouched (null-handdown keeps legacy trees exact).
- **CI**: `billing-test` job (dart:stable container, `flutter test`); e2e
  untouched (debug APK = free flavor, sideloadable, tips show §6 unavailable
  states — verified, nothing broken).

## 9. Out of scope / ops

E7 ships the trio *inside* the Pro flavor (gates read `FeatureFlags.pro`, not
billing) + widgets/backup/analytics. E8 help/store copy (Pro listing, "paid
only ever adds" promise, final BMC handle — open question 3). E9: Play Console
setup — second listing + price $7.99, three tip consumables, internal track
for *both* SKUs, Data-Safety forms (purchases processed by Google; we collect
nothing — unchanged). E10: iOS pair (StoreKit tips + paid-app mechanics) on the
decision-11 trigger. The v1 §9 unlock machinery is withdrawn from every epic.
