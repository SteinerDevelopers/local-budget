#!/usr/bin/env bash
# CI wrapper for the Glance dex gate (launch blocker 2026-11-23).
# Canonical checker: tools/ci/widget_dex_gate.py (stdlib-only dex parse —
# linkage lives in the method-id/proto tables, NOT in raw byte strings, so a
# grep fallback is impossible). The e2e image may lack python3, so try a
# best-effort install first; a probe that still cannot run exits non-zero
# with its own name — silence never reads clean (playbook measurement M9).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -lt 1 ]; then echo "widget-dex-gate: no artifact given" >&2; exit 2; fi

if ! command -v python3 >/dev/null 2>&1; then
  # Debian/Ubuntu e2e base; harmless no-op where apt does not exist.
  (apt-get update -qq && apt-get install -y -qq --no-install-recommends python3) >/dev/null 2>&1 || true
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "widget-dex-gate: python3 unavailable (and apt install failed) — cannot adjudicate $*" >&2
  exit 2
fi
exec python3 "$here/widget_dex_gate.py" "$@"
