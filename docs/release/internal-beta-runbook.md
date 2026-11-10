# Internal beta on the personal Play account, then migrate to the business account

Owner plan (2026-11-09): the **personal** Play Console account hosts the
**internal-testing track only** — no production, **no sales**, no
public listing. The D&B application is submitted; when it issues, the LLC
opens a business organization account and the app migrates. Only after
the migration may the app be sold or released to production.

Why the constraint set matters to Google's rules (sources read
2026-11-09; Console screens are authoritative over this doc):

- Internal testing needs no review and no tester quota. The
  12-testers-continuous-14-days requirement gates only *production
  access on personal accounts* — we never apply for production there.
- An account that **never monetizes** stays eligible for the direct
  **account-owner transfer** (the account itself moves to the LLC).
  Creating even one IAP product, ad declaration, or paid listing on the
  personal account forfeits that route and drops us to the slower
  app-transfer path (which re-creates tester groups and leaves
  account-level reports behind).
  **So: nothing monetizing is ever *created* on the personal account —
  not even test-then-delete; treat creation itself as forfeit.** The
  Pro unlock ships only on the business account. (Whether a deleted
  artifact still counts is undisclosed — the safe reading is the tight
  one.)
- Organization accounts must carry the legal name and address that
  match the D&B record and the Google payments profile. Set the personal
  account's **public developer name** to the exact D&B legal name at
  creation (punctuation included); a later name change triggers re-review
  and propagation delay, so do it before the beta, not at migration time.

## Phase 0 — owner, before the account hosts anything

- [ ] Personal Play account: identity verification, 2SV, recovery
      contacts, and a **second trusted admin** (no single-person
      custody of the app's home).
- [ ] Public developer name (the Play Console account's developer-name
      field) = exact LLC legal name as filed for D&B — expected
      "Steiner Developers, L.L.C." per `docs/store/listing.md`; verify
      against the issued D&B record, character for character. Not the
      app title (`Steiner Budget`), which is a separate field.
- [ ] Play Console user for the agent (release uploads + tester lists;
      owner-only roles stay owner's).

## Phase 1 — internal beta (personal account)

- [ ] Signed artifact: `package-aab-release-free` (the #47 job) on a
      green pipeline of the current `main`; identity = that pipeline sha,
      recorded in the track release notes of the upload.
- [ ] Prerequisite forms before first upload: privacy policy URL live
      (#10 · E9 Release checklist), Data safety answers, content
      rating, listing metadata per `docs/store/listing.md` (Name
      *Steiner Budget*, full name *Steiner's Private Budget*; Developer
      per Phase 0), **countries: United States only**.
      Data safety draft must be verified against the app's real behavior
      (no analytics; the cloud backup is user-initiated, end-to-end
      encrypted, into the user's own storage) — verify, don't copy.
- [ ] Internal tester list from `beta/tester-list.csv` rows with
      `status=collected` (Lance: **both** Google accounts, per the
      owner's CSV note). Signups with `status=signup` (currently Ravn,
      ravnstar06661@gmail.com) move to `collected` **only on an
      explicit owner word — never auto-promote** (law 4), then join the
      list. Which Google account *hosts* the Console is the owner's
      separate choice; hosting is not a tester row and vice versa.
- [ ] Beta comms run through `hello@steinerdevelopers.dev`; every tester
      report lands as an issue note (report-only law).
- [ ] Builds ship only from MR-merged `main`; kit identity law unchanged
      (pipeline sha pinned in every receipt).
- [ ] Pro flavor: **not** uploaded during phase 1. If ever uploaded,
      still no products/pricing — the monetization freeze is the
      migration-eligibility asset.

## Phase 2 — migration (after D&B issues; owner executes)

- [ ] Pre-transfer keystore sanity (owner-side, decision-13 custody):
      `keytool -list` against the upload keystore prints the expected
      alias, and the backup copy verifies — before any transfer screen
      is opened, not after.

Route A (primary): **account-owner transfer** — available only because
phase 1 never monetized. Both sides complete identity checks; the
account record (tracks, internal testers, listing) stays in place —
verify the tester list is untouched before announcing anything.

Route B (fallback, if Console denies route A for our account state —
undisclosed until the screen is seen): **app transfer** — installs,
ratings, version history and the package move; **tester groups do not**:
re-create the internal list on the business account and send testers one
re-link email (template needs the owner's approval — it is user-facing
copy).

Both routes: freeze releases while the transfer processes (Google's
latency is undisclosed; plan between beta waves), keep both accounts in
good standing, keep the upload keystore untouched (decision-13 custody —
Play App Signing does not rotate on transfer).

## Phase 3 — business account, only after migration

- [ ] Google payments profile (business) with legal name/address
      matching D&B to the character; tax info before any sale.
- [ ] Pro products created here, first time; then closed testing →
      production (organization accounts are exempt from the personal
      12×14 gate).

## Abort / hold notes

- A blocked transfer is a stop-and-report event, not a workaround event
  (no second personal account, no name improvisation).
- If the beta cohort grows past internal-testing limits (100), the
  closed track is still fine on the personal account; production is not.
- If Google changes account-transfer or track rules mid-beta, this doc
  is superseded by the Console: stop and report, don't improvise against
  the old rules.
- D&B issuance time is undisclosed. If it stalls past the planned beta
  waves, the hold/continue call is the owner's — the runbook sets no
  deadline the machine can't keep.
