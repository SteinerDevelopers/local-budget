# Data Safety inventory — Steiner Budget (Android)

_E9 groundwork, 2026-11-05. Derived from the actual merged manifest of the
current shipping APKs (dcf8c39), not from plugin READMEs. Verified by
extracting the string pool of `AndroidManifest.xml` from both flavor
artifacts. Re-verify against the release artifact before submitting the
Play Console Data Safety form._

## Headline answers (Play Console form)

- **Data collected: none.** No analytics, no crash reporting, no
  telemetry, no account. Transactions, categories, attachments (receipt
  photos/PDFs), budget rules and goals live only in the app's private
  SQLite file + files dir. Deleting the app removes everything; in-app
  "Erase all data" wipes immediately (E5).
- **Data shared: none with the developer.** The only network traffic is
  user-initiated and user-directed: optional FX rate lookups
  (`packages/data/lib/src/fx_service.dart`, one GET, sends only the
  currency pair) and Pro's encrypted WebDAV backup/sync **to the user's
  own server**. Nothing reaches Steiner Developers; uninstall removes
  everything. Per Play policy these are declared as user-initiated
  device functions, not data collection.
- **Encryption at rest:** Android default (app-private dir, File
  Encrypted Keystore volumes on every supported device). Export files
  (CSV/OFX) are user-initiated and land wherever the user picks.
- **Declared data-safety answer for all categories:** "Data is not
  collected." (Feasibility §3.1 zero-data stance; matches the
  pre-filled form in `docs/store/listing.md`.)

> **Release blocker found while writing this (2026-11-05):** the
> release manifest does **not** declare `INTERNET` — it only appears in
> debug kits via `src/debug/AndroidManifest.xml`. Today the FX rate
> fetch and WebDAV sync are user-initiated features whose code ships in
> release; without `INTERNET` they would fail (gracefully — FxService
> swallows socket errors — but silently, which is worse). The E9
> release prep must add `<uses-permission android:name=
> "android.permission.INTERNET"/>` to `src/main/AndroidManifest.xml`
> with a purpose comment, and re-run this audit. (Alternative — strip
> the features from release — contradicts decisions 7/9; not on the
> table.) This document is the record of why the permission exists.

## Permissions actually held (merged manifest, free + pro debug, dcf8c39)

Requested at install/runtime by the app or a library it links:

| Permission | Where from | Purpose string (Help Center + runtime rationale) |
|---|---|---|
| `POST_NOTIFICATIONS` | app (main manifest) | "Morning reminders for bills you asked the app to watch." Runtime prompt only when a bill with reminders is created (Android 13+). |
| `RECEIVE_BOOT_COMPLETED` | `workmanager` | Re-schedules the daily bill-materialization tick after a reboot so reminders survive restarts. No data read at boot. |
| `WAKE_LOCK` | `workmanager` | Lets the scheduled day-tick finish when the device is idle. |
| `FOREGROUND_SERVICE` (+`SHORT_SERVICE`) | `workmanager` | Keeps the day-tick alive long enough to complete on low-RAM devices. |
| `ACCESS_NETWORK_STATE` | plugins (workmanager/billing probes) | State check only; the app opens no connections by itself — every connection in release is user-initiated (FX rate, Pro backup; see the INTERNET row below). |
| `VIBRATE` | Flutter framework default | Haptic tick on save/correction/error (§4.5 acceptance). |
| `com.android.vending.BILLING` | billing plugin (compiled into both flavors; purchase UI only live in pro) | One-time unlock purchase + tips via Play Billing. Purchase tokens go to Play, nothing else. |
| `com.google.android.gms.version`, `com.google.android.aicore` | `google_mlkit_text_recognition` / `google_mlkit_document_scanner` | Bind to on-device Google services: OCR and the document scanner run **on-device** in Google's own Vision/AI runtime; the image never leaves the phone and is not stored by the scanner. |
| `INTERNET` | **debug/profile overlay today; must move to `main` at release prep** (see blocker above) | User-initiated FX rate lookup + Pro WebDAV backup to the user's own server. Never used by a background job. |

Notably **absent**: `CAMERA`, `READ_MEDIA_*`/storage, `ACCESS_FINE_LOCATION`,
any ad or analytics SDK permission. The scanner does not request CAMERA
because `google_mlkit_document_scanner` launches Google Play Services'
scanner UI — the camera is held by Google's remote process under its own
grant, same model as the system QR scanner. Gallery import goes through
the Android photo picker (per-photo grant, no `READ_MEDIA_IMAGES`).

## Store-data statements to mirror

- `docs/legal/privacy-policy.md` (owner-published copy) — must say the
  same thing in human terms; link goes in the listing.
- `docs/store/listing.md` — "your data never leaves your phone" line is
  only true while this page holds; any PR that adds a network call must
  update all three.

## Verification recipe (repeat on the release artifact)

```
python3 - <<'PY'
import zipfile, re
z = zipfile.ZipFile('app-release.apk')
am = z.read('AndroidManifest.xml')
for s in sorted({s.decode('utf-16le') for s in
    re.findall(rb'(?:[\x20-\x7e]\x00){5,}', am)
    if s.decode('utf-16le').startswith(('android.permission','com.'))}):
    print(s)
PY
```

Expected delta vs the table above: `INTERNET` disappears (no debug
overlay). Anything else appearing = re-audit before upload.
