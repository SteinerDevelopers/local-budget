#!/usr/bin/env bash
# phone_loop.sh — one-command on-device import capture loop (E11).
#
# Pushes a sample image, drives the import flow on the Coosea SL219A
# test phone (720x1600 @260dpi — re-derive TAPS for other devices), and
# scrapes the debug OCR trace the app prints as `[ocr-lines] ...`
# (debugPrint → Logcat tag `flutter`; needs a build with the debugPrint
# dump, i.e. >= 629ad4c).
#
# The system photo picker is multi-select on this device: `import`
# selects the newest thumbnail and STOPS; `confirm` presses Done.
# Two steps because the picker layout shifts with the cloud card.
#
# Usage:
#   LB_DEVICE=192.168.1.226:PORT ./tool/phone_loop.sh pair    <ip:pair-port> <6-digit-code>
#   LB_DEVICE=192.168.1.226:PORT ./tool/phone_loop.sh connect
#   LB_DEVICE=192.168.1.226:PORT ./tool/phone_loop.sh import  <image-file> [name]
#   LB_DEVICE=192.168.1.226:PORT ./tool/phone_loop.sh confirm [name]
#
# Env knobs: ADB (path to adb), PKG (flavor package, free default),
# OUT_DIR (screenshot/ocr output), CAPTURE_SECS, LAUNCH_WAIT_SECS.
# NOTE for agent/CI-ish shells: anything adb derives from HOME must be
# pinned first (e.g. `export HOME=...` or an env.sh) or adb SIGABRTs on
# "Cannot mkdir /home/node/.android".
set -euo pipefail

ADB="${ADB:-adb}"
PKG="${PKG:-dev.steiner.local_budget}"
OUT_DIR="${OUT_DIR:-phone-shots}"
# The SL219A test phone is a low-end SoC: full-page statement OCR takes
# 30-45 s after Done. Keep CAPTURE_SECS well above the slowest observed
# OCR run or the trace is cut off mid-document.
CAPTURE_SECS="${CAPTURE_SECS:-90}"
LAUNCH_WAIT_SECS="${LAUNCH_WAIT_SECS:-6}"
# SL219A recipe (verified 2026-11-05): [Add from a document] -> [Photos]
ENTRY_TAP="555 1332"; PHOTOS_TAP="137 1008"
THUMB_TAP="${THUMB_TAP:-120 1010}"   # newest image, top-left slot
DONE_TAP="608 1485"

need_device() { [[ -n "${LB_DEVICE:-}" ]] || { echo "!! set LB_DEVICE=<ip:port> (from Developer options → Wireless debugging)" >&2; exit 2; }; }
run() { echo "+ $ADB -s "$LB_DEVICE" $*" >&2; "$ADB" -s "$LB_DEVICE" "$@"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  pair)
    [[ $# -eq 2 ]] || { echo "usage: $0 pair <ip:pair-port> <6-digit-code>" >&2; exit 2; }
    # Pairing port != connect port; both shown on the Wireless debugging screen.
    "$ADB" pair "$1" "$2"
    ;;
  connect)
    need_device; run connect "$LB_DEVICE"; run devices
    ;;
  import)
    need_device
    img="${1:?usage: $0 import <image-file> [name]}"
    name="${2:-$(basename "$img")}"
    name="${name%.*}"
    [[ -f "$img" ]] || { echo "!! no such file: $img" >&2; exit 2; }
    mkdir -p "$OUT_DIR"
    echo "$name" > "$OUT_DIR/.last-run"
    run push "$img" /sdcard/Pictures/"$name".jpg >/dev/null
    run shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d file:///sdcard/Pictures/"$name".jpg >/dev/null
    run shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
      run shell am start -n "$PKG/.MainActivity"
    sleep "$LAUNCH_WAIT_SECS"
    run shell input tap $ENTRY_TAP;  sleep 2
    run shell input tap $PHOTOS_TAP; sleep 4
    run shell input tap $THUMB_TAP;  sleep 1
    echo "selected $name — now run: $0 confirm"
    ;;
  confirm)
    need_device
    name="${1:-$(cat "$OUT_DIR/.last-run" 2>/dev/null || echo import)}"
    mkdir -p "$OUT_DIR"
    out="$OUT_DIR/$name.ocr.txt"; shot="$OUT_DIR/$name.png"
    run logcat -c || true
    ( timeout "$CAPTURE_SECS" "$ADB" -s "$LB_DEVICE" logcat -v brief -s flutter:V \
        | grep --line-buffered 'ocr-lines' > "$out" ) &
    cap=$!
    sleep 1
    run shell input tap $DONE_TAP
    # Slow device: the review screen only appears when OCR finishes;
    # poll until it does (up to CAPTURE_SECS), then grab the trace.
    sleep 30
    run exec-out screencap -p > "$shot" 2>/dev/null || true
    wait "$cap" || true
    echo "--- lines: $(grep -c . "$out" 2>/dev/null || echo 0) -> $out   screenshot: $shot"
    ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
