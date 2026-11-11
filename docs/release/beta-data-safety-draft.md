# Beta data-safety + privacy DRAFT (grounded, not published)

_See also `financial-declaration-determination.md` — the #54 financial-
features declaration determination (declare "Other: offline money
management"; no license docs triggered)._

_DRAFT — no sentence here is a published promise until the owner approves
it (Law 4: promise sentences are owner-only). Every answer below is
backed by instrumented code state with a pointer, per the measurement
law, so the form can be re-verified mechanically before submission._

## Play Console → App content → Data safety

**"Does this app collect or share user data?" — No (free flavor).**
- The free flavor's manifest REMOVES `INTERNET` outright — CI
  manifest-guard fails the build if it ever returns ("house promise law",
  `.gitlab-ci.yml` manifest-guard).
- No analytics, no ad SDKs, no crash telemetry. Regenerate the check at
  submission: `flutter pub deps | grep -iE "analytic|admob|firebase|sentry"`
  must print nothing.

**Pro flavor (paid, later listing update):** the app can sync to a
user-configured WebDAV endpoint — the user's own server. Developer-side
collection remains none; the transfer is user-directed. Declare:
- "Data is encrypted in transit" → YES, enforced by code: plain HTTP is
  rejected for every non-RFC1918/loopback host
  (`packages/data/lib/cloud/webdav_client.dart:72`).
- Backup/sync payloads are encrypted envelopes before they ever leave
  (`packages/data/lib/src/backup.dart`; the backup key is scrubbed before
  the toggle reads "off" — #51, CI-pinned by `auto_backup_test`).
- "Users can request data deletion" → uninstall deletes everything the
  app holds (private storage only; `allowBackup=false` + total
  data-extraction exclusions, MR !21, manifest-guard-pinned).

**Encryption at rest:** app DB is in the app-private data directory
(platform sandbox). No additional at-rest crypto is claimed — the form
must not overstate; if owners want at-rest claims later, that's a
feature + new draft.

## Privacy policy skeleton (store listing)

- We do not collect, transmit, or sell any user data. Steiner Budget
  works offline with no account required.
- Budget data is stored only on the user's device, in app-private
  storage; uninstalling removes it.
- Optional Pro subscription syncs encrypted backup envelopes to a
  user-provided server of the user's choosing; the developer operates no
  servers for this purpose.
- Contact for privacy questions: `hello@steinerdevelopers.dev`.
- `<LLC legal review pass — owner decides whether counsel eyes it before
  listing>`

## Release notes draft (internal-track "What's new")

_Promise-sentence class — owner approval required before use:_

> First private beta. Offline budgeting with receipt scan-to-entry
> (camera or photo), budgets with rollover, goals, and recurring rules.
> Everything stays on this device. Something wrong or weird? Tell us:
> beta@steinerdevelopers.dev — screenshots welcome, they decide.

## Pre-submission verification commands (run at RC cut, bank output)

```
flutter pub deps | grep -iE "analytic|admob|firebase|sentry" || echo "no telemetry deps"
grep -n 'INTERNET' app/android/app/src/free/AndroidManifest.xml   # must show tools:node="remove"
grep -n 'allowBackup' app/android/app/src/main/AndroidManifest.xml # must show false
```
