# Device measurement run — 2026-11-10 (internal beta, rc-polish §4.5)

Bench pair (owner ruling, 2026-11-09): **Flip6 + VERGE**. No Fold6; Fire TV is not a
test device. VERGE (260 dpi) is the §4.5 "mid-range reference" proxy; Flip6 (480 dpi)
is flagship-class.

| device | model | screen | OS | battery during run |
|---|---|---|---|---|
| Flip6 | SM-F766U1 | 1080×2520 @480dpi | Android 14 | ~50%, charging |
| VERGE | SL219A (T-Mobile) | 720×1600 @260dpi | Android 14 | 100%, charging |

**Kit identity (Law 5):** both phones ran the kit-release pipeline artifact for
`9248e418` (= `main` tip `9248e41`), free-debug flavor, pulled from the generic
package registry and `sha256sum -c` verified; installed `install -r` (data kept) and
the on-device `pm path` md5 (`acdbb144dae3d9e6a61fb5929879bd66`) matched the CI
artifact on both phones. `git merge-base --is-ancestor` proved the kit commit is on
`main`. No telemetry was read — every number below is hand-measured over adb.

**Fixtures:** ten corpus images pushed to `/sdcard/Pictures/betafix/` as
`scan_0..9.png` (media-DB verified) on both phones. The corpus glob
`packages/capture/tool/corpus/latin_*.png` holds 24 files; the exact ten used
(md5-matched against the device copies) and the push/regenerate commands are in
[`raw/fixtures-betafix.txt`](raw/fixtures-betafix.txt).

---

## Results vs the §4.5 bar

| leg | Flip6 | VERGE | grade |
|---|---|---|---|
| Scan → review → save (§4.5 bar: *10-scan median* < 30 s), photo path — per-path medians, n stated per cell | ready 7.3 s med (saved runs); manual-entry **32.9 s med (n=8)**; one auto-save observed **15.0 s (n=1)**; 9/10 saved | ready 14.0 s med; manual-entry **45.1 s med (n=9)**; one auto-save observed **25.7 s (n=1)**; 10/10 saved | ⚠ see Findings 1–3 |
| Cold start ×5 | **1304 ms** median (n=5, `am start -W TotalTime`, COLD) | **4496 ms** median wall-clock (home interactive, n=5); `coldstart_e.csv` holds a 6th row `cold0=18334` — a v9 warm-up probe, not a cold sample, excluded | measured — §4.5 states no cold-start bar, so no grade (VERGE drawn-signal gap: Finding 6) |
| Camera launch ×5 (§4.5: < 1 s) | 5.15–5.26 s | 7.7–8.1 s (3/5 clean) | ⚠ instrument + ML Kit (Finding 4) |
| gfxinfo, QuickAdd×8 + ledger swipe ×12 (§4.5: < 1% >16 ms) | **21.4%** (31/145) | **3.4%** (5/147) | ❌ on the bench numbers (Finding 5) |
| TalkBack pass | all screens semantic: **0 clickable-unlabeled** in Home / Bills / Budgets / Goals / QuickAdd / scan-chooser dumps | same (service enable/disable lifecycle verified; teardown proven `Bound services:{}` — captured in [`raw/hygiene-post-run.txt`](raw/hygiene-post-run.txt)) | ✅ (voice audio itself not machine-verifiable) |
| Font scale 2.0 | Home ✅, scan chooser ✅, picker ✅, QuickAdd ✅ | same: QuickAdd ✅ | ✅ — was Finding 2, reversed pm (see below) |

## Findings

1. **Scan totals on bench are manual, and the manual path is over the bar.** The
   free flavor without Gemini Nano (both bench devices) extracts no total from the
   synthetic corpus: the review sheet shows "No total found — type it in." for
   9–10/10 fixtures, so every scan saved through the manual keypad — manual median
   **32.9 s (Flip6, n=8) / 45.1 s (VERGE, n=9)**, both over the 30 s bar. The OCR
   auto-save path fired exactly **once per device** (scan4: 15.0 s / 25.7 s) — two
   observations, not medians: under the bar, but too thin to claim the bar met. The
   manual-vs-auto delta on that common basis is ≈ +18 s (Flip6) / +19 s (VERGE).
   `Save` is gated by `_canSave = money>0 && category!=null` — instruments and users
   must pick a category chip before the keypad alone enables it.
2. **[CORRECTED the same afternoon — this finding is REVERSED.]**
   ~~QuickAdd clips at font 2.0 on both devices~~. Re-adjudication of the SAME
   committed pixels with pixel-exact crops: the `$0` hero is intact on BOTH
   devices (Flip6 right edge at x≈1045 < 1080; the bright pixels at x=1079 are
   the sheet's SCROLLBAR THUMB, which was misread as a cut edge); the partial
   3rd category chip (`Trans…`) is the horizontal `ListView`'s scroll
   affordance (`CategoryChips` `chip-row`), not a clip; keypad "ballooning" is
   the Expanded-region layout choice. QuickAdd at 2.0 is clean on both phones.
   Lesson: a screenshot read by eye at scale is still an eyeball — measure
   extents before declaring a clip. (The widget suite that was written to
   chase this found two REAL overflow bugs elsewhere — source-sheet
   'Recent screenshot' row, review-sheet font escape — fixed separately.)
3. The scan-leg outlier is on **Flip6**: scan9 (`raw/flip6/scan_c.csv`) never
   reached the review sheet inside the window (ready 67.1 s, saved=0) — ML Kit
   retry-storm on that fixture. VERGE's scan9 is a clean 45.0 s save. All medians
   above are computed over saved runs, so the Flip6 medians rest on n=9/n=8.
4. The scan **camera** UI is `com.google.android.gms.mlkit.docscan` DocumentScanning
   (immersive, landscape for some lenses). The measured 5–8 s includes ML Kit activity
   cold-start + this ROM's first-launch immersive-mode confirmation dialog; the < 1 s
   bar needs a re-measure on a device that has already dismissed that dialog, or
   report it as the ML Kit floor.
5. **Jank**: Flip6 21.4% janky during scripted QuickAdd×8 + swipe×12. Small N
   (145 frames) and wireless adb injected touches inflate it; but the signal direction
   agrees on the flagship. VERGE 3.4% clears the flagship's number but still misses
   the <1% bar. Needs a repeat with
   `gfxinfo jank` over a longer window before RC sign-off; recorded honestly as-is.
6. **Mid-range drawn-signal gap (VERGE)**: `am start -W` returns `Status: timeout,
   LaunchState UNKNOWN(-1), WaitTime>10 s` — the activity paints (wall-clock home
   visible ≈4.5 s) but the framework fully-drawn signal never fires inside the window;
   `uiautomator` intermittently returns `null root node` during ledger shimmer
   (no-idle). Instruments must retry dumps; product side, consider
   `reportFullyDrawn()` after first ledger paint.

## Follow-through 2026-11-11 — Finding 4 re-measure (Tab A9+, kit c08254a7, debug)

The ML Kit confounder Finding 4 suspected is now directly characterized on the
Tab A9+ (dialog dismissed, model provisioned):

| leg | clean measurement | note |
|---|---|---|
| Camera row -> viewfinder | **1.02 s / 1.45 s** (n=2, pixel probe of the shutter ring) | debug kit; the 2026-11-10 5-8 s figures rode the ML Kit download/dialog |
| docscan activity open | `Displayed … docscan.ui.DocumentScanningActivity: +340 ms` (logcat) | Google's own UI cost, not app compute |
| Next -> our Review sheet | **0.55 s** (window-focus probe) | recognition finishes inside the gms activity before hand-back |

First-run reality check: with no provisioned model the very first Camera tap
opens Play-services full-screen "Downloading updates…" for ~3.5 min — any
camera number taken around a device's first scan measures provisioning, not
the app. Also structural: the current docscan flow inserts **two** confirmation
screens (Adjust corners, Enhance) between shutter and our Review sheet — two
extra taps ride inside the §4.5 30-s scan bar and belong to the E discussion.
Edge-hunt caveat: shutter->corners ran >30 s on a pitch-dark frame (ML Kit
searching for a document edge that is not there) — content-dependent, not an
app cost. The Review sheet re-verified its honest "No total found — type it
in." state with Save disabled; nothing was saved, bench DB untouched.

## Instrumentation notes (why some earlier files show failures)

- `instruments/battery.sh` first VERGE cold-start leg is INVALID (`MISS`/HOT lines: the
  photo-picker task stayed on top and the app's drawn-signal gap). Valid replacement:
  wall-clock `coldstart_e.csv` from `v8verge.sh`.
- v5/v6 scan legs (`scan_b/scan_c.csv` VERGE side, `scan_d`) died to the
  category-gated Save and this ROM's cold-launch tap swallow; valid scan data is
  `flip6/scan_c.csv` (chip-tap corrected) and `verge/scan_e.csv` (re-tap loop).
- Flip6 `exec-out screencap -p` corrupts because the device reports **multiple
  displays**. `battery.sh`/`fixpass.sh` predate the fix — that is the committed
  Flip6 `PNG-CORRUPT tbc-home-shot` line (its TalkBack-home verdict therefore rests
  on the dumps; the VERGE counterpart `tbc-home-shot` is png-ok). From `l5c.sh` on,
  instruments capture via `screencap -p <device-file>` + `cat`, PNG-magic-verified
  in-script (a ≥10 KB sanity read was manual, not scripted).
- VERGE font-2.0 and cleanup passes ran **inline** (not a committed script) with two
  tricks the earlier scripts lacked: `monkey` relaunch with `mCurrentFocus`
  front-verification (dumps enumerate background windows — one earlier "found Home"
  was actually the launcher on top), and re-tap loops for this ROM's cold-launch tap
  swallow. Their evidence is the committed shots/dumps (`e3-*.png/xml`).
- Bench hygiene after the run, both devices: captured in
  [`raw/hygiene-post-run.txt`](raw/hygiene-post-run.txt) — font_scale 1.0,
  accessibility off, `enabled_accessibility_services=null`, `Bound services:{}`,
  screen-off timeout restored (VERGE pre-run value was not captured; set to the
  stock 600000). Ledger restore: every battery-created row deleted through the
  product UI — Flip6 via repair.sh l7 sweep plus one accidental `camera_scan`
  capture removed by row→Delete; VERGE 26 rows (`vergeclean.sh` stdout in
  `raw/verge/summary.txt`). Proof is the DB sentinel recount in
  [`raw/dbverify.txt`](raw/dbverify.txt): zero rows at the run's sentinel amounts
  (12.25/12.34) on both phones, 12 txns Flip6 / 32 VERGE, owner dogfood and the two
  pre-existing owner `camera_scan` rows untouched (Flip6 row-diff vs the session
  baseline `/tmp/home.xml`, VERGE by sentinel grep-proven absent from baseline).

## Reproduce

`battery.sh`, `repair.sh`, `fixpass.sh` take `<serial>` as `$1` and write into
`/tmp/measure/<tag>/`; `v8verge.sh`, `v9verge.sh`, `l5c.sh`, `vergeclean.sh` have
the bench serials **hardcoded** (endpoints rotate — edit the `D=` line first).
`battery.sh` = cold/gfx/scan/camera legs; `v8verge.sh`/`v9verge.sh` = VERGE-corrected
cold/scan legs; `l5c.sh` = Flip6 font sweep; `vergeclean.sh` = ledger restore.
Push the fixtures first per `raw/fixtures-betafix.txt`. Raw `*.csv`/`*.txt` under
`raw/` are the untouched leg outputs; `gfx.txt` is the full `dumpsys gfxinfo`
capture; `dbverify.txt` + `hygiene-post-run.txt` are the post-run proofs.
Instrument integrity: from this directory, `sha256sum -c instruments/SHA256SUMS.txt`
(paths are relative to this directory, not `instruments/`).
