# Privacy policy — Local Budget

_Covered app: Local Budget (and Local Budget Pro), Android.
Version 1.0 — 2026-11-03._

## The short version

**Local Budget does not collect your data.** There is no account, no
server of ours, no analytics, no advertising SDK, no tracking. Your
transactions, balances, categories and receipt images are stored only
in the app's private storage on your device. Uninstalling the app
removes every byte it ever stored. If this policy ever reads
differently than the app does, the app is wrong and we want to hear
about it.

## What that means, concretely

- **No accounts.** The app works before you sign in to anything,
  because there is nothing to sign in to.
- **Nothing is transmitted to us.** We cannot see your finances, your
  receipt photos, or anything else you put in the app — not because we
  promise not to look, but because your data never reaches us.
- **No analytics or crash collectors.** We don't know which screens
  you use; we can't. Improvements are driven by people who choose to
  write to us.
- **No ads, no third-party SDKs with tracking.** Not now; a promise
  was made in the design notes and it will not be reversed for money.

## The three things that do touch a network — each one optional, each one you start

1. **Live FX rates.** Foreign-currency entries can fetch a
   conversion rate from a public rate API. It is a toggle in Settings
   (on by default, per device), and the request carries no personal
   data — only which currency pair you asked about. Turn it off and
   entries simply use the manual rate you give them.
2. **Pro cloud backup — to your storage, not ours.** If you buy Pro
   and configure your own WebDAV/Drive destination, the app uploads
   an **encrypted** snapshot of your ledger to the server **you**
   host or rent, encrypted with a passphrase **you** choose. We have
   no access to that server, and the encryption is real: a lost
   passphrase is unrecoverable, including by us.
3. **Your purchase.** If you unlock Pro, Google Play (or the App Store
   on iOS) processes the payment and handles receipts and
   restore-purchases. Their privacy policies cover that exchange; all
   the app sees is the entitlement, not your payment details.

## Permissions, in plain language

- **Camera** — photograph a receipt when you tap the camera button.
- **Photos (picker)** — import a receipt image or screenshot you pick.
  The app copies only the single item you chose into its own folder.
- **Storage/downloads access (only when you use it)** — import a PDF
  or statement you select, or restore/backup a file you point at.
  Includes the optional daily auto-backup to a folder you chose.

No permission is used in the background, and the app has no permission
to post, message, read contacts, or locate you.

## Children

The app is a budgeting utility for adults and is not directed at
children.

## Changes

If this policy changes, the app's About screen and this document will
carry the new version, and material changes will be announced in the
release notes. The core promise — *no collection* — is the product;
we do not plan to "change direction."

## Contact

Questions, corrections, or a feature you wish existed:
`<OWNER-CONTACT — fill before publishing>`.

---

### Notes for the store forms (not part of the published text)

- **Play Data Safety:** answer **“We collect nothing”** for data
  collection. The rate-fetch and your-own-storage backup are
  _device-function_ traffic the user initiates and does not reach the
  developer; declare permissions (camera, media picker) as
  user-facing functionality, not data collection.
- **Apple privacy labels:** no collectors — “Data Not Collected.”
- **TODO before publishing (owner):** host this file at a public URL
  (the GitLab Pages copy of this repo works), put that URL in the
  Play Console and App Store Connect privacy-policy fields, and fill
  the contact line above.
