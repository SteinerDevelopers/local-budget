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

**Fixtures:** the 10 corpus images `packages/capture/tool/corpus/latin_*.png` pushed
to `/sdcard/Pictures/betafix/` (media-DB verified) on both phones.

---

## Results vs the §4.5 bar

| leg | Flip6 | VERGE | grade |
|---|---|---|---|
| 10-scan median (§4.5: < 30 s), photo path | ready≈7.3 s; **32.7 s manual / 15.0 s auto**, 9/10 saved | ready≈14.0 s; **45.4 s manual / 25.7 s auto**, 10/10 saved | ⚠ see Findings 1–3 |
| Cold start ×5 | **1304 ms** median (`am start -W TotalTime`, COLD) | **4496 ms** median wall-clock (home interactive) | ✅ Flip6; ✅ VERGE |
| Camera launch ×5 (§4.5: < 1 s) | 5.15–5.26 s | 7.7–8.1 s (3/5 clean) | ⚠ instrument + ML Kit (Finding 4) |
| gfxinfo, QuickAdd×8 + ledger swipe ×12 (§4.5: < 1% >16 ms) | **21.4%** (31/145) | **3.4%** (5/147) | ❌ on the bench numbers (Finding 5) |
| TalkBack pass | all screens semantic: **0 clickable-unlabeled** in Home/Bills/Budgets/Goals/QuickAdd/Scan-menu dumps | same (service enable/disable lifecycle verified; teardown proven `Bound services:{}`) | ✅ (voice audio itself not machine-verifiable) |
| Font scale 2.0 | Home ✅, scan chooser ✅, picker ✅, **QuickAdd ✗** | same: **QuickAdd ✗** | ❌ Finding 2 |

## Findings

1. **Scan totals on bench are manual.** The free flavor without Gemini Nano (both
   bench devices) extracts no total from the synthetic corpus: the review sheet shows
   "No total found — type it in." for 9–10/10 fixtures and every scan is saved through
   the manual keypad. That is the *designed* review-first fallback, but it means the
   < 30 s median is only met on the OCR path; the manual-entry path costs ≈ +18 s
   (Flip6) / +31 s (VERGE). The keypad also requires first tapping the amount field
   (`Save` is gated by `_canSave = money>0 && category!=null` — instruments and users
   must pick a category chip).
2. **QuickAdd clips at font 2.0 on both devices.** Screenshot-adjudicated: the `$0`
   amount overflows the right edge (glyph cut), the 3rd category chip clips
   (`Trans…`), keypad rows balloon with dead space. Home/Bills/scan-chooser are clean
   at 2×. The overflow suite covers 1.0×/1.3× @320 dp only — add a 2.0× QuickAdd case.
3. VERGE scan leg had one OCR outlier (scan9, Flip6: 67 s to sheet, saved=0) —
   ML Kit retry storm on a low-contrast fixture; median reported excluding it.
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

## Instrumentation notes (why some earlier files show failures)

- `instruments/battery.sh` first VERGE cold-start leg is INVALID (`MISS`/HOT lines: the
  photo-picker task stayed on top and the app's drawn-signal gap). Valid replacement:
  wall-clock `coldstart_e.csv` from `v8verge.sh`.
- v5/v6 scan legs (`scan_b/scan_c.csv` VERGE side, `scan_d`) died to the
  category-gated Save and this ROM's cold-launch tap swallow; valid scan data is
  `flip6/scan_c.csv` (chip-tap corrected) and `verge/scan_e.csv` (re-tap loop).
- Flip6 `exec-out screencap -p` corrupts because the device reports **multiple
  displays**; the instruments switched to `screencap -p <file>` + `cat` (all valid
  shots are ≥10 KB and PNG-header-verified; pixel adjudication per Law 5).
- Bench hygiene after the run, both devices: font_scale 1.0, accessibility off and
  **unbound**, screen-off timeout restored, picker/TalkBack force-stopped, and every
  battery-created ledger row deleted through the product UI (Flip6: 11 rows incl. one
  accidental `camera_scan` capture; VERGE: 26 rows) with the app DB re-pulled and
  counted to zero sentinels. Owner dogfood rows untouched (baseline-grep proven).

## Reproduce

See each script header; they take `<serial>` and write into `/tmp/measure/<tag>/`.
`battery.sh` = cold/gfx/scan/camera legs; `v8verge.sh`/`v9verge.sh` = VERGE-corrected
cold/scan legs; `l5c.sh` = Flip6 font sweep; `vergeclean.sh` = ledger restore. Raw
`*.csv`/`*.txt` in `raw/` are the untouched leg outputs; `gfx.txt` is the full
`dumpsys gfxinfo` capture.
