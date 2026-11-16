# Steiner Budget

Offline-first, zero-data receipt-scanning budget app for Android (launch) and iOS (activated on traction — decision 11).

- **Feasibility & requirements:** [docs/feasibility.md](docs/feasibility.md) — 11 locked decisions, feature spec, monetization model
- **Project plan:** [docs/project-plan.md](docs/project-plan.md) — milestones M0–M4, epics E0–E10, testing & risk plan
- **Agent & contributor contract:** [AGENTS.md](AGENTS.md) — rule zero: consult the shared agent playbook before every dev cycle (decision 15)

Free tier is feature-complete. A one-time unlock sells own-cloud backup, widgets, and an analytics pack. No ads. No data collection — a literal store promise.

> ### The house promise
> **“Your privacy is more important than our profit.”**
> The rule every Steiner Developers decision passes through (owner,
> 2026-11-07), and in this repo it is measured, not asserted: the free
> release APK carries **no INTERNET permission** — the free flavor removes
> it from the merge, and a CI job pins that line (aapt-verified
> 2026-11-07). Only the Pro flavor declares the network, for own-cloud
> sync that is end-to-end encrypted before it leaves your phone. Receipts,
> ledgers, and images never move unless you point them at your own server.
> [steinerdevelopers.dev/privacy](https://steinerdevelopers.dev/privacy)

## Install — direct APK (0.1.1) or Play (0.1.2+3)

> Channels move at their own speed: this direct-APK rail currently serves
> **0.1.1**; the Google Play closed-testing rail carries **0.1.2+3**.

- **Direct APK — no Google account or Play required:**
  [steiner-budget-0.1.1-free-release.apk](https://dl.steinerdevelopers.dev/releases/steiner-budget-0.1.1-free-release.apk)
  (release-key signed; the free flavor carries **no INTERNET permission**).
  Verify the binary against its published checksum before installing:
  [SHA-256 manifest](https://dl.steinerdevelopers.dev/releases/steiner-budget-0.1.1-manifest.txt).
- **Google Play (closed testing):**
  [opt-in page](https://play.google.com/apps/testing/dev.steiner.local_budget) —
  then install "Steiner Budget" from the Store. Play and direct-APK channels
  sign differently and can't upgrade over each other; pick one per device.

## License

Copyright (C) 2026 Steiner Developers, L.L.C.

This program is free software licensed under the **GNU Affero General
Public License v3** (see `LICENSE`), with an additional permission
permitting conveyance when combined with Google's ML Kit Text Recognition
SDK (the on-device receipt OCR dependency), as described at the end of the
`LICENSE` file. SPDX identifier: `AGPL-3.0-or-later` — the FSF header
grants later versions at the user's option.

The free Google Play build and the direct-download APK are built from this
source. Release practice for this project is to publish each release as a
signed tag with the signing certificate fingerprint and a SHA-256
manifest, so any published binary can be tied back to its source.
