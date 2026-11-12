#!/usr/bin/env bash
# shoot.sh — store-screenshot rig for the Saturday device window (#55 queue).
# Operator-driven per device laws (walks re-dump before taps; screenshots
# adjudicate). This script does NOT tap: it standardizes everything around
# the taps — session dir, dark mode, names, resolution, validation, ledger.
#
#   ./tools/store/shoot.sh <serial> start   # session begin: pm clear + dark
#   ./tools/store/shoot.sh <serial> <name>  # capture shot <name> AFTER you
#                                           #   navigated (verify on-screen!)
#   ./tools/store/shoot.sh <serial> done    # validate all 8, write manifest
#
# Shot names (docs/store/listing.md checklist, in story order):
#   01-month  02-capture-review  03-detail-attachment  04-budgets-near-limit
#   05-budget-vs-actual  06-import-preview  07-help-search  08-about-promise
#
# Pre-registered session law: seed a TIDY month by QuickAdd (~12 entries,
# real-looking amounts, one receipt attachment; NO e2e junk, NO real data);
# green-bar budget per §2.1; teardown = pm clear AFTER `done` (never leave
# demo rows for the soak's next cycle — bench hygiene law).
set -eu
ADB=${ADB:-adb}; SERIAL=${1:?serial}; MODE=${2:?start|<name>|done}
PKG=dev.steiner.local_budget
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESS="$SELF/.session"
DIR="$SELF/out/$( [ -f "$SESS" ] && cat "$SESS" || date -u +%Y%m%dT%H%M%SZ)"
A() { timeout 20 $ADB -s "$SERIAL" "$@"; }
case "$MODE" in
  start)
    date -u +%Y%m%dT%H%M%SZ > "$SESS"
    mkdir -p "$DIR"
    A shell pm clear "$PKG" >/dev/null
    A shell cmd uimode night yes || true   # dark mode, held for the session
    A shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    echo "session $DIR — seed the tidy month now; screenshot-adjudicate each entry before the next"
    ;;
  done)
    /workspace/Workspace/tools/python/bin/python3 - "$DIR" <<'PY'
import sys, os, struct
want = ['01-month','02-capture-review','03-detail-attachment','04-budgets-near-limit',
        '05-budget-vs-actual','06-import-preview','07-help-search','08-about-promise']
d = sys.argv[1]; missing=[]; lines=[]
for w in want:
    f=os.path.join(d, w+'.png')
    if not os.path.exists(f): missing.append(w); continue
    with open(f,'rb') as fh:
        fh.read(16); w_,h_ = struct.unpack('>II', fh.read(8))
    ok = (h_/w_) >= 1.7   # portrait-ish; exact 9:16 crop happens at upload console
    lines.append(f"{w}: {w_}x{h_} {'OK' if ok else 'BAD-ASPECT'}")
print('\n'.join(lines))
open(os.path.join(d,'manifest.txt'),'w').write('\n'.join(lines)+'\n')
if missing: print('MISSING:', ' '.join(missing)); sys.exit(1)
print('8/8 captured — operator visual QC per listing.md remains REQUIRED (script verifies geometry, not content)')
PY
    ;;
  *)
    F="$DIR/$MODE.png"
    A exec-out screencap -p > "$F"
    echo "$F"
    echo "ADJUDICATE NOW (device law): does the shot show exactly the listing.md item '$MODE' promises?"
    ;;
esac
