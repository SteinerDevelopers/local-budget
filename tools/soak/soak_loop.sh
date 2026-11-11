#!/usr/bin/env bash
# soak_loop.sh — the 2026-11-11 bench soak driver (owner soak word).
#
# One sequential driver for the dedicated bench pair (Tab A9+ + VERGE;
# Flip6 is the owner's personal device and off the roster by owner order
# 2026-11-11) — sequential on purpose so two flutter processes never
# contend the SDK lock. Each cycle per device:
#   1. the committed jank probe (FrameTiming percentiles, profile AOT);
#   2. the draft drill: phase 1 types 42.5 + Food and holds; the HOST
#      force-stops the app (real process death); phase 2 relaunches,
#      asserts the verbatim restore, SAVES it (restored state must
#      complete, and saving is what clears the draft for the next loop);
#   3. crash-buffer delta, PSS total, battery level.
# Every cycle appends one JSONL line to soak.jsonl; raw drive logs go to
# logs/. Kit identity is the three md5s pinned in KIT-IDENTITY.txt —
# flutter drive installs the given prebuilt binary, so no rebuild can
# silently change the subject under test.
#
# usage: soak_loop.sh <hours> [gap_seconds]
#        env KIT_DIR (kit-*.apk dir), SOAK_DIR (output dir)
set -u
export PATH=/workspace/Workspace/tools/flutter/bin:/workspace/Workspace/tools/android-sdk/platform-tools:$PATH
export PUB_CACHE=/workspace/Workspace/tools/pub-cache HOME=/workspace/Workspace/tools/home
REPO=${REPO:-/workspace/Workspace/budget-project/local-budget-app/app}
KIT=${KIT_DIR:-/workspace/Workspace/soak/kit}
OUT=${SOAK_DIR:-/workspace/Workspace/soak/2026-11-11}
PKG=dev.steiner.local_budget
HOURS=${1:-72}
GAP=${2:-1800}
END=$(( $(date +%s) + HOURS * 3600 ))
mkdir -p "$OUT/logs"
DEVS=("192.168.1.123:40589|tablet" "192.168.1.226:41283|verge")

jline() { # $1 dev  $2 payload-without-ts/dev
  printf '{"ts":"%s","dev":"%s"%s}\n' "$(date -u +%FT%TZ)" "$1" "$2" \
    >> "$OUT/soak.jsonl"
}
dev_live() { adb -s "$1" shell true >/dev/null 2>&1; }
crashes() { adb -s "$1" logcat -b crash -d 2>/dev/null | grep -c "FATAL EXCEPTION"; }
pss() { adb -s "$1" shell dumpsys meminfo "$PKG" 2>/dev/null | awk '/^TOTAL/{print $2; exit}' | tr -d '\r'; }
batt() { adb -s "$1" shell dumpsys battery 2>/dev/null | awk -F': ' '/level/{print $2; exit}' | tr -d '\r'; }
num() { [ -z "$1" ] && echo null || echo "$1"; }

drive() { # serial apk target logfile -> prints exit code
  # --keep-app-running is the modern form of the device law (--no-uninstall
  # app — and the DB holding the draft — down after every session. The
  # first soak smoke caught it exactly this way (drafts vanished because
  # the previous phase UNINSTALLED, not because the kill was real).
  ( cd "$REPO" && timeout 600 flutter drive --profile --flavor free --keep-app-running \
      -d "$1" \
      --use-application-binary "$2" --driver integration_test/driver.dart \
      --target "integration_test/$3" ) > "$4" 2>&1
  echo $?
}

while [ "$(date +%s)" -lt "$END" ]; do
  for entry in "${DEVS[@]}"; do
    serial=${entry%%|*}; dev=${entry##*|}
    if ! dev_live "$serial"; then
      adb connect "$serial" >/dev/null 2>&1
      dev_live "$serial" || { jline "$dev" ',"event":"device-down"'; continue; }
    fi
    c0=$(crashes "$serial")
    ts=$(date +%Y%m%dT%H%M%SZ)

    rcj=$(drive "$serial" "$KIT/kit-jank.apk" jank_probe_test.dart \
          "$OUT/logs/$ts-$dev-jank.log")
    jl=$(grep -E "JANK" "$OUT/logs/$ts-$dev-jank.log" | tail -3 | tr '\n' '~')

    # Draft drill phase 1: drive in background; kill the app once the
    # READY marker proves the debounced draft write has landed.
    d1="$OUT/logs/$ts-$dev-d1.log"
    ( cd "$REPO" && timeout 300 flutter drive --profile --flavor free --keep-app-running \
        -d "$serial" \
        --use-application-binary "$KIT/kit-d1.apk" \
        --driver integration_test/driver.dart \
        --target integration_test/draft_phase1_test.dart ) > "$d1" 2>&1 &
    dp=$!
    ready=0
    for _ in $(seq 1 75); do
      grep -q "DRAFT-READY" "$d1" 2>/dev/null && { ready=1; break; }
      sleep 2
    done
    if [ "$ready" = 1 ]; then
      adb -s "$serial" shell am force-stop "$PKG"
    fi
    sleep 3
    kill "$dp" 2>/dev/null; wait "$dp" 2>/dev/null
    [ "$ready" = 1 ] || jline "$dev" ',"event":"draft-phase1-no-marker"'

    rc2=$(drive "$serial" "$KIT/kit-d2.apk" draft_phase2_test.dart \
          "$OUT/logs/$ts-$dev-d2.log")
    pass=$(grep -c "DRAFT-PASS" "$OUT/logs/$ts-$dev-d2.log")
    leak=$(grep -c "DRAFT-LEAK" "$d1")
    c1=$(crashes "$serial")
    jline "$dev" ",\"jank\":\"$jl\",\"draft_pass\":$pass,\"draft_leak\":$leak,\"pss_kb\":$(num "$(pss "$serial")"),\"crash_delta\":$((c1 - c0)),\"battery\":$(num "$(batt "$serial")"),\"rc_jank\":$rcj,\"rc_phase2\":$rc2"
  done
  sleep "$GAP"
done
echo "SOAK-COMPLETE $(date -u +%FT%TZ)"
