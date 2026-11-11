# Tab A9+ first wide-surface audit + #44/#45 device closure — 2026-11-10

Device: Samsung Tab A9+ (SM-X210), Android 16 / API 36, screencap 1200x1920 px
at density 1.5 → 800x1280 dp, smallestWidth bucket **sw800**. Bench role:
third permanent bench device (owner ruling 2026-11-10: full bench member);
connected over wireless debugging (port rotates per session; pairing persists).

Kit identity: branch head `15ae8632` (= main `3487489e` + tests-only a11y
commit; lib byte-identical to main), debug flavor `free`,
apk md5 `d0000a006029557ebc7c798f7cc6548d` (`md5sum
app/build/app/outputs/flutter-apk/app-free-debug.apk` regenerates the check).
Normalized for the audit: font_scale 1.0 (was 1.1), rotation locked, single
display. Teardown left everything normalized and restored; `--no-uninstall`.

## #44 + #45 closed on-device (evidence trail)

Real fixture `docs/store/assets/walmart-receipt-2026-09-11.png`, clean ledger,
Add from receipt → Photos (SAF picker):

| shot | content |
|---|---|
| `23-review-walmartk.png` | scan #1 prefill reproduces the bounce honestly: `Walmartk`, amount 69.93 — no stored merchant, nothing to match (by design) |
| `24-review-corrected.png` | payee corrected to `Walmart`, date Today |
| `25-row-sublabel.png` | ledger row `Food / Walmart / −$69.93` — the #45 sub-label fix, measured at sw800 |
| `26-rescue-prefill.png` | scan #2 of the same receipt: prefill **auto-resolves to `Walmart`** — the #44 tail-appendage rescue works on tablet width |
| `27-detail-payee.png` | detail sheet: store-icon payee row `Walmart` + stored original image (the `WMP PRIVATE LABEL CREDIT` lines visible) |

Issue notes with the same shots: #44 note 547, #45 note 549. No closes —
owner's word. #46 unchanged: still waiting on a re-scan of the original
bill photo (no shape evidence to fix the missed $36 Amount-Due).

## Width/scale matrix (kit 15ae8632)

| screen | portrait 1.0 | landscape 1.0 | portrait 2.0 |
|---|---|---|---|
| ledger empty/one-row | `01-launch-portrait.png` ok | `L01–L02-ledger.png` ok | `F201-ledger.png` ok (row grows — #48 fix holds) |
| source sheet | `21-source-sheet.png` ok | — | — |
| SAF picker (system) | `22-picker.png` ok | — | — |
| scan review sheet | `23/24` ok | — | not re-shot (phone guards cover) |
| entry detail | `27-detail-payee.png` ok | `L01` (survived rotation) | — |
| QuickAdd | — | `L03-quickadd.png` — adapts to centered dialog ✓ | `F202-quickadd.png` ok, chip row scrolls |
| Manage | — | `L04-manage.png` ok | — |
| Help list | — | `L05-help.png` ok | `F203-help.png` ok, 14/14 articles |
| Help article | — | `L07-article.png` ok | — |
| Budgets panel | — | `L06-budgets.png` ok | — |

Overflow detector: debug-build logcat — `logcat -c` before each screen,
`logcat -d | grep overflowed | grep -v adbd` after (the `grep -v adbd` is
mandatory: the adb command itself echoes into logcat and false-positives the
count). Result: **zero real RenderFlex overflows** across the whole matrix.

## Findings

- **T1 (retracted, method lesson filed):** first sweeps suggested the bottom
  CTAs were untappable at tablet width ("nav hijack"). Retracted: all misses
  were **coordinates eyeballed from downscaled image previews**; the glyph
  text actually sits ~30–60 px higher than the preview suggested
  (measured bbox `y 1666–1693`). Lesson: every device tap is aimed from a
  pixel-probe of the raw PNG (`tprobe` one-liner below), never from a
  preview render. CTAs work fine.
- **T2 (cosmetic, wide-surface):** at ≥sw800 the balance strip occupies the
  left ~63 % of the header (dead band right of NET) and landscape article
  paragraphs run full 1920 px (line length ~200 chars). Nothing breaks; both
  say "designed for phones". Owner-relevant only if tablets are claimed at
  launch (manifest today has no width gate — see E8 note in issue #51 thread).
- Open question (not asserted): at 2.0 QuickAdd showed Transport chip
  highlighted with a one-Food-row ledger (L03). Warm-category default logic
  is unit-tested on phone; tablet repro not pinned — re-check before treating
  as a bug.
- Method notes (also in playbook): wireless debugging on Android 16 tablets
  idles itself off — keep the panel open during walks; input coordinate space
  is 1:1 physical px (no offset — verified by top/mid/bottom controls).

## Reproduce the probes

```
adb -s <host:port> shell 'screencap -p /sdcard/w.png' && \
adb -s <host:port> exec-out cat /sdcard/w.png > shot.png
# then probe accent-text clusters for tap targets (raw PNG, not previews):
python3 -c 'from PIL import Image; ...'  # see playbook device-walk-laws
```
