#!/usr/bin/env bash
# probe.sh — §A (issue #55) timeline probe: attribute VERGE sheet jank to
# raster- vs UI-thread cost. Run ONLY when the bench is free (post-soak or a
# planned A/B window); never against a running soak loop (serial contention).
#
# Recipe (playbook frame-budget probe, extended with threadslice):
#   ./tools/jank/probe.sh <serial> <label> [seconds=12]
# Produces $OUT/{gfxinfo-before.txt, gfxinfo-after.txt, trace.perfetto-trace,
# framestats.txt} and prints the raster/ui split summary.
#
# A/B discipline (pre-registered 2026-11-12, issue #55 note 80x):
# - same kit trio md5s, same keeper/port regime, samples only from draft-pass
#   cycles; compare per-sheet medians, not aggregate frames.
# - baseline receipt: soak/jank-baseline-2026-11-12.md (VERGE SHEET p99 106ms).
set -eu
SERIAL=${1:?usage: probe.sh <serial> <label> [seconds]}
LABEL=${2:?label required (e.g. before-fix-2026-11-14)}
SECS=${3:-12}
PKG=dev.steiner.local_budget
ADB=${ADB:-adb}
OUT=$(dirname "$0")/out/$(date -u +%Y%m%dT%H%M%SZ)-$LABEL
mkdir -p "$OUT"
timeout 15 $ADB -s "$SERIAL" shell dumpsys gfxinfo "$PKG" reset >/dev/null
timeout 15 $ADB -s "$SERIAL" shell dumpsys gfxinfo "$PKG" > "$OUT/gfxinfo-before.txt"
# perfetto: base sched + gfx + freq + atrace apps for frame slices
timeout $((SECS+30)) $ADB -s "$SERIAL" shell perfetto \
  -c - --txt -o /data/misc/perfetto-traces/probe.trace <<EOF > "$OUT/perfetto-config.txt"
buffers { size_kb: 32768 }
duration_ms: $((SECS*1000))
data_sources {
  config {
    name: "android.ftrace"
    ftrace_config {
      ftrace_events: "sched/sched_switch"
      ftrace_events: "power/suspend_resume"
      atrace_categories: "gfx"
      atrace_categories: "view"
      atrace_categories: "sched"
      atrace_categories: "freq"
      atrace_apps: "$PKG"
    }
  }
}
EOF
# drive the sheet while tracing: the loop's drive() is the trusted workload;
# if running standalone, scroll the ledger instead (kept dumb on purpose):
timeout $((SECS+60)) $ADB -s "$SERIAL" shell input swipe 500 1400 500 400 300 || true
timeout 20 $ADB -s "$SERIAL" pull /data/misc/perfetto-traces/probe.trace "$OUT/trace.perfetto-trace" >/dev/null
timeout 15 $ADB -s "$SERIAL" shell dumpsys gfxinfo "$PKG" framestats > "$OUT/framestats.txt"
timeout 15 $ADB -s "$SERIAL" shell dumpsys gfxinfo "$PKG" > "$OUT/gfxinfo-after.txt"
python3 "$(dirname "$0")/parse_probe.py" "$OUT" | tee "$OUT/summary.txt"
echo "probe artifacts: $OUT"
