# LocalBudget (working name)

Offline-first, zero-data receipt-scanning budget app for Android (launch) and iOS (activated on traction — decision 11).

- **Feasibility & requirements:** [docs/feasibility.md](docs/feasibility.md) — 11 locked decisions, feature spec, monetization model
- **Project plan:** [docs/project-plan.md](docs/project-plan.md) — milestones M0–M4, epics E0–E10, testing & risk plan

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
