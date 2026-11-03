# E5 Design Spec — Data layer (export · backup · import · FX · integrity)

**Plan ref:** E5 (issue #6). Guardrail §3.4: data access & hygiene are **free
forever** — nothing in this epic may hide behind the paywall; the paid
own-cloud backup (E6/E7) wraps *these* primitives, it does not replace them.
The one network touch is the optional FX lookup (feasibility decision 8:
"your data never leaves your device" stays literally true — the lookup sends
two currency codes and a date, nothing else, and never user records).

Status: draft 2026-11-02.

## 1. Where it lives

All logic in `packages/data` (domain), all pickers/share in the app shell.
New `data:` section at the bottom of the **Manage tab** (no new tab — same
place base currency already lives): *Export CSV · Back up now · Restore from
backup · Import statement · Live FX rates (toggle)*.

New package deps (pure Dart where possible): `archive`, `pointycastle`
(AES-GCM/PBKDF2), `http`, `xml` in `data`; `share_plus` (export/backup out)
and `file_picker` (import/restore in — SAF `OPEN_DOCUMENT` on Android,
document picker on iOS, per feasibility §5 file-handling decision) in `app`.

## 2. CSV export (free, lossless-enough, re-importable)

- One file per run, UTF-8, RFC 4180, CRLF; header
  `date,description,category,note,amount,currency,account`.
- Amount is **signed decimal** in the row's own currency: expenses negative,
  income positive — the bank convention, so the same mapping UI (§4) reads
  our own exports back. Goal transfers (`goalId != null`) are **not** ledger
  entries and stay out (E3 §3.5 rule).
- `description` prefers merchant name, falls back to note; `date` ISO
  `YYYY-MM-DD`. Rows sorted date→id. Account filter (per account or all).
- Written to a temp file, handed to the share sheet; title
  `budget-export-<yyyy-MM-dd>.csv`.

## 3. Encrypted backup / restore (free)

- Container `.lzbak`: `LZBK1` magic, version byte, KDF params
  (PBKDF2-HMAC-SHA256, 600 000 iters, 16 B salt), 12 B nonce, then the whole
  zip sealed with **AES-256-GCM** (AAD = header). Password is never stored;
  wrong password ⇒ AEAD tag fail ⇒ "Wrong password or corrupt file".
- Zip contents: `manifest.json` (app version, **schemaVersion**, createdAt,
  attachment count), `ledger.db`, `attachments/<original names>`.
- The DB snapshot is taken with `VACUUM INTO` (atomic, consistent, WAL-free)
  while the app keeps running; attachments are copied from the app-private
  store (same relative names `attachment_store` uses).
- **Restore**: pick file → passphrase → verify header/tag → refuse if the
  file's schemaVersion is newer than this build ("update the app first") →
  checkpoint + replace the live DB with the snapshot and replace the
  `attachments/` directory **whole** — restore is a coherent device-state
  rollback, so files added after the backup go too (names are timestamped
  with `-2` collision suffixes, not content-hashed: same-name-different-
  bytes overwriting would corrupt live `imageRef`s otherwise). → reopen DB
  and cold-restart the UI stack. Restore is the only destructive path and
  asks once, explicitly, naming both casualties (ledger + attachments).
- Output goes through the share sheet like export (Save to Files / Drive).

## 4. CSV import (mapping profiles, preview, conservative dedupe)

- Wizard (full-screen sheet, 4 steps): **File → Map → Preview → Commit**.
- Parser: hand-rolled RFC 4180 (quotes, embedded commas/newlines, CRLF);
  delimiter sniffed from the first line (`,` `;` tab).
- **Mapping**: dropdowns for date / description / amount (or separate debit
  & credit) / category / note, pre-filled by header-name heuristics
  (`date|transdate…`, `description|payee…`, `amount|debit…`). Date format
  detected from samples across `yyyy-MM-dd`, `dd/MM/yyyy`, `MM/dd/yyyy`,
  `dd.MM.yyyy` (ambiguous samples ⇒ ask, don't guess).
- **Saved per-bank profiles**: after a successful commit the mapping is
  stored in `settings` as `import.csv.<profileName>` (JSON: header row,
  column roles, date format, debit/credit polarity). Next file whose header
  row matches exactly ⇒ profile applies, one tap to confirm instead of the
  whole mapping step; profiles list/manage lives on the same wizard step.
- **Dedupe (conservative, §issue)**: a row is a duplicate iff a ledger row
  exists with the same (accountId, dateDays, amountMinor, isIncome) —
  nothing fuzzier, never silent merges. If the row carries a bank FITID and
  the target account has any `externalId` values (v6, §5), an exact
  externalId match also marks a duplicate. Duplicates default **off** in the
  preview checklist; user can force-include any of them.
- Preview: count summary (N new / M duplicates), first ~50 rows in a table
  with per-row checkboxes; amounts normalized to minor units with the
  account's currency exponent. Commit = one transaction batch, `source =
  import`, into the account chosen in step 3; result toast "N imported".

## 5. OFX import + schema v6 (`externalId`)

- OFX 1.x **XML** documents only (issue wording "standard XML"); SGML-ish
  OFX (no closing tags) is explicitly out of scope v1 — parser detects it
  and says so instead of half-parsing. Currency comes from `CURDEF`, so
  no mapping UI is needed; the wizard re-enters at Preview.
- Sign convention per spec: negative `TRNAMT` = expense (maps straight to
  our unsigned + isIncome storage). `DTPOSTED` parsed to epoch days.
- **v6 migration**: `transactions.externalId TEXT NULL` + unique partial
  index `(accountId, externalId) WHERE externalId NOT NULL` — FITID
  becomes the strongest dedupe key for incremental bank re-imports. Ships
  with the standing per-bump test (`migration_v6_test.dart`), same shape
  as v4/v5. OFX writes FITID there; CSV import leaves it null.

## 6. FX lookup — the one network touch, and its offline twin

- Toggle in Manage (*Live FX rates*, default on, per-device, no account).
- Provider: **frankfurter.dev** (ECB reference rates; no key, no account,
  plain GET `https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR`,
  verified live 2026-11-02 — the older `.app` host 301s and must not be
  used). Requests contain only the two ISO codes + date. Injectable
  `http.Client` everywhere (tests never hit the network).
- On save in a foreign currency: fresh same-day cached rate ⇒ use it; else
  fetch (2 s budget); else store `fxRate/baseAmountMinor = null` — the row
  **still saves** (boot/entry never block, global rule) and carries an
  amber "No rate" chip in review + detail with a manual-rate field.
- A successful fetch re-labels rows *for that day* that are still
  `null` (pending-conversion sweep, one statement, opportunistic only —
  never a spinner, never a background timer).
- Rates cache in `settings` (`fx.USD-EUR.2026-11-02 → 0.93`) and expire
  same-day; no historical series is kept (zero telemetry posture).

## 7. Integrity & the migration story

- Standing rule, now written down: **every schema bump ships a
  `migration_v<N>_test.dart`** that opens the previous schema fixture and
  asserts data survives (pattern already pinned for v4/v5).
- On boot, off the critical path (never blocks first frame): `PRAGMA
  integrity_check` + `PRAGMA foreign_keys` assertion + `PRAGMA
  foreign_key_check`; failures are logged and surfaced as a passive
  Settings banner ("Database check found problems — export a backup now"),
  never a dialog and never a crash.
- WAL checkpoint before any snapshot (export list, backup) so a restore is
  never missing recent commits.

## 8. Test & CI surface

- Unit (data pkg): CSV encode/decode round-trips incl. quoted fields; OFX
  fixtures (valid, SGML-reject, tz variants); dedupe triples incl. FITID
  path; crypto envelope round-trip + wrong-password + tamper; VACUUM INTO
  snapshot restores with rows visible; FX with fake client (fresh/stale/
  error/offline states); migration v6 test.
- Widget (app): export writes the expected file; import wizard end-to-end
  with a temp CSV (profile save + reapply); backup→wipe→restore round-trip
  on a temp dir; Manage at 1.3× (a11y gate grows).
- Goldens: `manage_data_*`, `import_map`, `import_preview`,
  `backup_passphrase` via CI generate job.
- e2e-android: extends the existing journey — export CSV to a temp dir via
  the share path and assert the file exists (plugin-level; no UI automator
  needed for SAF sheet).
