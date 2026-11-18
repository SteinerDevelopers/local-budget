# Play App Signing — the law for new apps

Owner ruling 2026-11-17: **every new Steiner app ships through Play App
Signing** — Google holds the app signing key (the Console's default path) and
re-signs every artifact; our keystore is demoted to an **upload key**, and its
certificate can be rotated from the Console without ever touching users.

## Where each app stands

| App | Signing identity | Why |
|---|---|---|
| Steiner Budget (free) | self-signed (decision 13) | created before the ruling; converting needs a Play signing-key migration — only on owner instruction |
| Steiner Budget Pro | **Play App Signing** | new app; the ruling applies at birth |

The upload keystore is deliberately the **same** keystore the free lane
already guards — the existing custody plan (encrypted blob in two clouds,
passphrase split) covers it, and Play lets us rotate the upload key later
from the Console if the owner ever wants a separate key. No new ceremony.

## Pro first upload — owner's rails (once)

1. Play Console → create app for `dev.steiner.local_budget_pro` (new listing;
   store rails are owner-only per process law).
2. On protected `main`, play the `package-aab-release-pro` CI job. It refuses
   early without the signing secrets, pins the Pro flavor pairing, and prints
   the upload certificate's SHA-256 before building.
3. Download `out/app-pro-release.aab` from the job artifacts.
4. Upload to the internal track, **accepting Google-managed app signing** —
   do *not* pick "I'll manage my own app signing key" (that path is the free
   app's history, not the law).
5. Confirm the Console's *upload key fingerprint* matches the SHA-256 the job
   printed, step by step: the same two numbers, no copy-paste across boxes.
6. Upload `out/app-pro-release-mapping.txt` to the private crash-symbolication
   section (never ships to users).

From then on every Pro artifact follows steps 2–6; the app signing key lives
in Google's infrastructure and simply works. Vocabulary for the listing
itself follows the app's own words ("entries", "receipt photos") — the
listing-assets work drafts it when the freeze lifts.
