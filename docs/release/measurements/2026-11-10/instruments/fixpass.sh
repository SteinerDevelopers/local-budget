#!/bin/bash
# Final instrument pass (v6):
#  verge: unstick TalkBack (v4 bug: never actually disabled; dump fails under it)
#  l3c:   scan x10 with CATEGORY CHIP tap (product rule: _canSave = money>0 AND category!=null)
#  l1c:   cold start x5 (LaunchState-aware)
#  l4c:   camera x5
#  l6c:   TalkBack semantic walk WITH working dumps (both devices), verify-off after
# Usage: fixpass.sh <serial> <tag> <modes>   (modes: tbfix,l3c,l1c,l4c,l6c,l7)
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=$1; TAG=$2; MODES=,$3,
OUT=/tmp/measure/$TAG; mkdir -p "$OUT"
PY=/workspace/Workspace/tools/python/bin/python3
PKG=dev.steiner.local_budget; PICK=com.google.android.photopicker; TB=com.google.android.marvin.talkback
fresh(){ $ADB -s "$D" shell am force-stop $TB 2>/dev/null; $ADB -s "$D" shell am force-stop $PICK; $ADB -s "$D" shell am force-stop $PKG; sleep 2
  $ADB -s "$D" shell am start -n $PKG/.MainActivity >/dev/null; sleep 5
  dump "$OUT/.xcur.xml"; grep -q 'content-desc="Add receipt"' "$OUT/.xcur.xml"; }
dump(){ # retry: this ROM intermittently returns "null root node"
  for t in 1 2 3 4; do
    $ADB -s "$D" shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1
    $ADB -s "$D" exec-out cat /data/local/tmp/x.xml > "$1" 2>/dev/null
    [ $(wc -c < "$1") -gt 2000 ] && return 0
    sleep 1.5
  done
  return 1
}
findc(){ $PY - "$1" "$2" <<'PYEOF'
import re,sys
pat=sys.argv[1]
x=open(sys.argv[2],encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0); d=re.search(r'content-desc="([^"]*)"',n)
    if not d: continue
    dv=d.group(1).replace('&#10;','\n')
    ok = dv.startswith(pat[1:]) if pat.startswith('%') else (dv==pat)
    if ok:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(1)
PYEOF
}
td(){ local n=$1 t=${2:-10} t0=$(date +%s%3N) xy
  while :; do dump "$OUT/.xcur.xml"
    xy=$(findc "$n" "$OUT/.xcur.xml") && { $ADB -s "$D" shell input tap $xy; return 0; }
    [ $(( $(date +%s%3N)-t0 )) -gt $((t*1000)) ] && { echo "MISS:$n" >> "$OUT/misses.log"; return 1; }
    sleep 0.4; done
}
wd(){ local n=$1 t=${2:-20} t0=$(date +%s%3N)
  while :; do dump "$OUT/.xcur.xml"
    findc "$n" "$OUT/.xcur.xml" >/dev/null && return 0
    [ $(( $(date +%s%3N)-t0 )) -gt $((t*1000)) ] && return 1
    sleep 0.4; done
}
shot(){ $ADB -s "$D" exec-out screencap -p > "$OUT/$1.png"; head -c 4 "$OUT/$1.png" | grep -q PNG && echo "png-ok $1" >> "$OUT/summary.txt" || echo "PNG-CORRUPT $1" >> "$OUT/summary.txt"; }

if [[ $MODES == *,tbfix,* ]]; then
  $ADB -s "$D" shell am force-stop $TB
  $ADB -s "$D" shell settings put secure accessibility_enabled 0
  $ADB -s "$D" shell settings put secure enabled_accessibility_services ""
  sleep 2
  echo "tb-after: '$($ADB -s "$D" shell settings get secure enabled_accessibility_services | tr -d '\r')' enabled=$($ADB -s "$D" shell settings get secure accessibility_enabled | tr -d '\r')" >> "$OUT/summary.txt"
  $ADB -s "$D" shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1 && echo "dump-restored" >> "$OUT/summary.txt"
fi

if [[ $MODES == *,l1c,* ]]; then
  : > "$OUT/coldstart_c.csv"
  for i in 1 2 3 4 5; do
    $ADB -s "$D" shell am force-stop $TB; $ADB -s "$D" shell am force-stop $PICK; $ADB -s "$D" shell am force-stop $PKG; sleep 3
    OUTW=$($ADB -s "$D" shell am start -W -n $PKG/.MainActivity | tr -d '\r')
    TT=$(echo "$OUTW" | sed -n 's/^TotalTime: \([0-9]*\).*/\1/p')
    ST=$(echo "$OUTW" | sed -n 's/^LaunchState: \([A-Z]*\).*/\1/p')
    echo "cold$i state=${ST:-?} ms=${TT:-?}" >> "$OUT/coldstart_c.csv"
  done
fi

if [[ $MODES == *,l3c,* ]]; then
  : > "$OUT/scan_c.csv"; : > "$OUT/createdc.log"
  for i in $(seq 0 9); do
    fresh || { echo "scan$i FRESH-FAIL" >> "$OUT/scan_c.csv"; continue; }
    dump "$OUT/.xpre.xml"
    td "Scan a receipt" 15 || { echo "scan$i SCAN-MISS" >> "$OUT/scan_c.csv"; continue; }
    td "Photos" 10 || { echo "scan$i PHOTOS-MISS" >> "$OUT/scan_c.csv"; continue; }
    sleep 2; dump "$OUT/.xpick.xml"
    XY=$($PY - "$OUT/.xpick.xml" "$i" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
i=int(sys.argv[2]); c=[]
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0)
    if not re.search(r'content-desc="Photo taken',n): continue
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
    if b:
        x1,y1,x2,y2=map(int,b.groups()); c.append((y1,x1,x2,y2))
if c:
    c.sort(); y1,x1,x2,y2=c[min(i,len(c)-1)]; print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
    [ -z "$XY" ] && { echo "scan$i PICK-MISS" >> "$OUT/scan_c.csv"; continue; }
    T0=$(date +%s%3N); $ADB -s "$D" shell input tap $XY; sleep 1.5
    dump "$OUT/.xpick2.xml"
    DX=$($PY - "$OUT/.xpick2.xml" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
hb=max((int(v) for v in re.findall(r'bounds="\[\d+,\d+\]\[\d+,(\d+)\]"',x)), default=2400)
c=[]
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0)
    if 'android.widget.Button' not in n: continue
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
    if not b: continue
    x1,y1,x2,y2=map(int,b.groups())
    if y1>hb-260 and (x1+x2)/2>540: c.append((x1,x2,y1,y2))
if c:
    c.sort(reverse=True); x1,x2,y1,y2=c[0]; print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
    [ -n "$DX" ] && $ADB -s "$D" shell input tap $DX
    tmo=$(( $(date +%s%3N)+60000 )); READY=0; MANUAL=0
    while :; do dump "$OUT/.xrev.xml"
      grep -q 'content-desc="Save' "$OUT/.xrev.xml" && { READY=1; break; }
      [ $(date +%s%3N) -gt $tmo ] && break; sleep 0.6; done
    R1=$(date +%s%3N)
    if [ $READY = 1 ]; then
      if grep -q 'No total found' "$OUT/.xrev.xml"; then
        MANUAL=1
        td "%Amount" 6
        td $'1\n1' 6; td $'2\n2' 6; td $'.\n.' 6; td $'3\n3' 6; td $'4\n4' 6
        dump "$OUT/.xrev2.xml"; grep -q 'Amount 12\.34' "$OUT/.xrev2.xml" || echo "scan$i AMOUNT-FAIL" >> "$OUT/scan_c.csv"
      fi
      td "Food" 8
      td "Save" 8
    fi
    SAVED=0; wd "Add receipt" 30 && SAVED=1
    S1=$(date +%s%3N)
    echo "scan$i ready_ms=$((R1-T0)) total_ms=$((S1-T0)) manual=$MANUAL saved=$SAVED" >> "$OUT/scan_c.csv"
    dump "$OUT/.xpost.xml"
    $PY - "$OUT/.xpre.xml" "$OUT/.xpost.xml" "$OUT/createdc.log" <<'PYEOF'
import re,sys
def rows(p):
    try: x=open(p,encoding='utf-8',errors='ignore').read()
    except: return set()
    out=set()
    for m in re.finditer(r'content-desc="([^"]*)"',x):
        d=m.group(1).replace('&#10;','\n').replace('&amp;','&').replace('&quot;','"').replace('&apos;',"'")
        if d.endswith(', Today'): out.add(d)
    return out
a,b,out=rows(sys.argv[1]),rows(sys.argv[2]),sys.argv[3]
for n in sorted(b-a):
    open(out,'a').write(n+'\n')
PYEOF
  done
fi

if [[ $MODES == *,l4c,* ]]; then
  : > "$OUT/camera_c.csv"
  for i in 1 2 3 4 5; do
    fresh || { echo "cam$i FRESH-FAIL" >> "$OUT/camera_c.csv"; continue; }
    td "Scan a receipt" 15 || { echo "cam$i SCAN-MISS" >> "$OUT/camera_c.csv"; continue; }
    T0=$(date +%s%3N); td "Camera" 10 || { echo "cam$i TAP-MISS" >> "$OUT/camera_c.csv"; continue; }
    tmo=$(( $(date +%s%3N)+15000 )); OK=0
    while :; do dump "$OUT/.xcam.xml"
      grep -q 'content-desc="Capture"' "$OUT/.xcam.xml" && { OK=1; break; }
      [ $(date +%s%3N) -gt $tmo ] && break; sleep 0.15; done
    echo "cam$i $(( $(date +%s%3N)-T0 )) ms $([ $OK = 1 ] && echo ok || echo TIMEOUT)" >> "$OUT/camera_c.csv"
  done
fi

if [[ $MODES == *,l6c,* ]]; then
  $ADB -s "$D" shell am force-stop $TB
  $ADB -s "$D" shell settings put secure enabled_accessibility_services "$TB/.TalkBackService"
  $ADB -s "$D" shell settings put secure accessibility_enabled 1
  sleep 3; $ADB -s "$D" shell monkey -p $TB -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
  dump "$OUT/tbc-check.xml"
  grep -qi "talkback" "$OUT/tbc-check.xml" && echo "tb-dialog-seen" >> "$OUT/summary.txt"
  $ADB -s "$D" shell input keyevent KEYCODE_BACK; sleep 2
  fresh && dump "$OUT/tbc-home.xml"
  td "%Bills" 15;   sleep 1; dump "$OUT/tbc-bills.xml"
  td "%Budgets" 15; sleep 1; dump "$OUT/tbc-budgets.xml"
  td "%Goals" 15;   sleep 1; dump "$OUT/tbc-goals.xml"
  td "Add receipt" 15; sleep 1; dump "$OUT/tbc-quickadd.xml"; td "%Scrim" 6
  td "Scan a receipt" 15; sleep 1; dump "$OUT/tbc-scanmenu.xml"; td "%Scrim" 6
  shot tbc-home-shot
  $ADB -s "$D" shell am force-stop $TB
  $ADB -s "$D" shell settings put secure accessibility_enabled 0
  $ADB -s "$D" shell settings put secure enabled_accessibility_services ""
  sleep 2
  echo "tb-off: enabled='$($ADB -s "$D" shell settings get secure accessibility_enabled | tr -d '\r')' svcs='$($ADB -s "$D" shell settings get secure enabled_accessibility_services | tr -d '\r')'" >> "$OUT/summary.txt"
fi

touch "$OUT/FIXPASS-DONE"
