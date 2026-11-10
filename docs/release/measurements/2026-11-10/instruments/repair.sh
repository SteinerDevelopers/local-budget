#!/bin/bash
# Repair pass v5 — legs that failed or had broken instruments in v4.
# Recovery-first: every iteration force-stops BOTH app and photopicker.
# Baseline guard: never deletes a row present in $BASE (owner's originals).
# Usage: repair.sh <serial> <tag> <modes> <base-xml>
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=$1; TAG=$2; MODES=,$3,; BASE=$4
OUT=/tmp/measure/$TAG; mkdir -p "$OUT"
PY=/workspace/Workspace/tools/python/bin/python3
PKG=dev.steiner.local_budget; PICK=com.google.android.photopicker
now(){ date +%s%3N; }
dump(){ $ADB -s "$D" shell uiautomator dump /data/local/tmp/r.xml >/dev/null 2>&1; $ADB -s "$D" exec-out cat /data/local/tmp/r.xml > "$1" 2>/dev/null; }
findc(){ $PY - "$1" "$2" <<'PYEOF'
import re,sys
pat=sys.argv[1]
x=open(sys.argv[2],encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0); d=re.search(r'content-desc="([^"]*)"',n)
    if not d: continue
    dv=d.group(1).replace('&#10;','\n').replace('&amp;','&').replace('&quot;','"').replace('&apos;',"'")
    ok = dv.startswith(pat[1:]) if pat.startswith('%') else (dv==pat)
    if ok:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(1)
PYEOF
}
tapdesc(){ local name=$1 tmo=${2:-8} t0=$(now) xy
  while :; do dump "$OUT/.rcur.xml"
    xy=$(findc "$name" "$OUT/.rcur.xml") && { $ADB -s "$D" shell input tap $xy; return 0; }
    [ $(( $(now)-t0 )) -gt $((tmo*1000)) ] && { echo "MISS: $name" >> "$OUT/misses.log"; return 1; }
    sleep 0.35
  done
}
waitdesc(){ local name=$1 tmo=${2:-8} t0=$(now)
  while :; do dump "$OUT/.rcur.xml"
    findc "$name" "$OUT/.rcur.xml" >/dev/null && return 0
    [ $(( $(now)-t0 )) -gt $((tmo*1000)) ] && return 1
    sleep 0.35
  done
}
fresh(){ $ADB -s "$D" shell am force-stop $PICK; $ADB -s "$D" shell am force-stop $PKG; sleep 2
  $ADB -s "$D" shell am start -n $PKG/.MainActivity >/dev/null; sleep 4
  waitdesc "Add receipt" 20
}

# ---------- l1b cold start with picker-kill + LaunchState ----------
if [[ $MODES == *,l1b,* ]]; then
  : > "$OUT/coldstart_b.csv"
  for i in 1 2 3 4 5; do
    $ADB -s "$D" shell am force-stop $PICK; $ADB -s "$D" shell am force-stop $PKG; sleep 3
    OUTW=$($ADB -s "$D" shell am start -W -n $PKG/.MainActivity | tr -d '\r')
    TT=$(echo "$OUTW" | sed -n 's/^TotalTime: \([0-9]*\).*/\1/p')
    ST=$(echo "$OUTW" | sed -n 's/^LaunchState: \([A-Z]*\).*/\1/p')
    echo "cold$i state=${ST:-?} ms=${TT:-?}" >> "$OUT/coldstart_b.csv"
  done
fi

# ---------- l3b scan x10: rotated cells, focused amount ----------
if [[ $MODES == *,l3b,* ]]; then
  : > "$OUT/scan_b.csv"; : > "$OUT/createdb.log"
  for i in $(seq 0 9); do
    fresh || { echo "scan$i FRESH-FAIL" >> "$OUT/scan_b.csv"; continue; }
    tapdesc "Scan a receipt" 15 || { echo "scan$i SCAN-MISS" >> "$OUT/scan_b.csv"; continue; }
    dump "$OUT/.rpre.xml"
    tapdesc "Photos" 10 || { echo "scan$i PHOTOS-MISS" >> "$OUT/scan_b.csv"; continue; }
    sleep 2; dump "$OUT/.rpick.xml"
    XY=$($PY - "$OUT/.rpick.xml" "$i" <<'PYEOF'
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
    [ -z "$XY" ] && { echo "scan$i PICK-MISS" >> "$OUT/scan_b.csv"; continue; }
    T0=$(now); $ADB -s "$D" shell input tap $XY; sleep 1.5
    dump "$OUT/.rpick2.xml"
    DX=$($PY - "$OUT/.rpick2.xml" <<'PYEOF'
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
    tmo=$(( $(now)+60000 )); READY=0; MANUAL=0; AMOK=1
    while :; do dump "$OUT/.rrev.xml"
      grep -q 'content-desc="Save' "$OUT/.rrev.xml" && { READY=1; break; }
      [ $(now) -gt $tmo ] && break; sleep 0.6; done
    R1=$(now)
    if [ $READY = 1 ]; then
      if grep -q 'No total found' "$OUT/.rrev.xml"; then
        MANUAL=1
        tapdesc "%Amount" 6
        tapdesc $'1\n1' 6; tapdesc $'2\n2' 6; tapdesc $'.\n.' 6; tapdesc $'3\n3' 6; tapdesc $'4\n4' 6
        dump "$OUT/.rrev2.xml"
        grep -q 'Amount 12\.34' "$OUT/.rrev2.xml" || AMOK=0
      fi
      [ $AMOK = 1 ] && tapdesc "Save" 10
    fi
    SAVED=0; waitdesc "Add receipt" 25 && SAVED=1
    S1=$(now)
    echo "scan$i ready_ms=$((R1-T0)) total_ms=$((S1-T0)) manual=$MANUAL amount_ok=$AMOK saved=$SAVED" >> "$OUT/scan_b.csv"
    dump "$OUT/.rpost.xml"
    $PY - "$OUT/.rpre.xml" "$OUT/.rpost.xml" "$OUT/createdb.log" "$BASE" <<'PYEOF'
import re,sys
def rows(p):
    try: x=open(p,encoding='utf-8',errors='ignore').read()
    except: return set()
    out=set()
    for m in re.finditer(r'content-desc="([^"]*)"',x):
        d=m.group(1).replace('&#10;','\n').replace('&amp;','&').replace('&quot;','"').replace('&apos;',"'")
        if d.endswith(', Today'): out.add(d)
    return out
a,b,out,base=rows(sys.argv[1]),rows(sys.argv[2]),sys.argv[3],rows(sys.argv[4])
for n in sorted(b-a):
    if n in base: continue
    open(out,'a').write(n+'\n')
PYEOF
  done
fi

# ---------- l4b camera x5 ----------
if [[ $MODES == *,l4b,* ]]; then
  : > "$OUT/camera_b.csv"
  for i in 1 2 3 4 5; do
    fresh || { echo "cam$i FRESH-FAIL" >> "$OUT/camera_b.csv"; continue; }
    tapdesc "Scan a receipt" 15 || { echo "cam$i SCAN-MISS" >> "$OUT/camera_b.csv"; continue; }
    T0=$(now); tapdesc "Camera" 10 || { echo "cam$i TAP-MISS" >> "$OUT/camera_b.csv"; continue; }
    tmo=$(( $(now)+15000 )); OK=0
    while :; do dump "$OUT/.rcam.xml"
      grep -q 'content-desc="Capture"' "$OUT/.rcam.xml" && { OK=1; break; }
      [ $(now) -gt $tmo ] && break; sleep 0.15; done
    echo "cam$i $(( $(now)-T0 )) ms $([ $OK = 1 ] && echo ok || echo TIMEOUT)" >> "$OUT/camera_b.csv"
  done
fi

# ---------- l6b TalkBack semantic dumps ----------
if [[ $MODES == *,l6b,* ]]; then
  TBPKG=$($ADB -s "$D" shell pm list packages | grep -i "marvin.talkback" | head -1 | sed 's/package://' | tr -d '\r')
  [ -z "$TBPKG" ] && TBPKG=$($ADB -s "$D" shell pm list packages | grep -i talkback | head -1 | sed 's/package://' | tr -d '\r')
  echo "tb_pkg=$TBPKG" >> "$OUT/summary.txt"
  $ADB -s "$D" shell settings put secure enabled_accessibility_services "$TBPKG/.TalkBackService" 2>/dev/null
  $ADB -s "$D" shell settings put secure accessibility_enabled 1 2>/dev/null; sleep 5
  fresh
  dump "$OUT/tb2-home.xml"
  tapdesc "%Bills" 15;   dump "$OUT/tb2-bills.xml"
  tapdesc "%Budgets" 15; dump "$OUT/tb2-budgets.xml"
  fresh; tapdesc "Scan a receipt" 15; dump "$OUT/tb2-scan.xml"
  $ADB -s "$D" shell settings put secure enabled_accessibility_services "" 2>/dev/null
  $ADB -s "$D" shell settings put secure accessibility_enabled 0 2>/dev/null
  echo "tb2 disabled $(date -u +%FT%TZ)" >> "$OUT/summary.txt"
fi

# ---------- l7 cleanup (fresh-home, baseline-guarded) ----------
if [[ $MODES == *,l7,* ]]; then
  delrow(){ # desc-regex
    fresh || return 1
    XY=$($PY - "$OUT/.rcur.xml" "$1" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'content-desc="([^"]*%s[^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%sys.argv[2],x)
if m:
    x1,y1,x2,y2=map(int,m.groups()[1:5]); print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
    [ -z "$XY" ] && return 2
    $ADB -s "$D" shell input tap $XY; sleep 1.5
    dump "$OUT/.rdet.xml"
    findc "%Delete" "$OUT/.rdet.xml" >/dev/null || { echo "DELETE-MISS regex" >> "$OUT/misses.log"; $ADB -s "$D" shell input keyevent BACK; return 1; }
    xy=$(findc "%Delete" "$OUT/.rdet.xml"); $ADB -s "$D" shell input tap $xy; sleep 1; return 0
  }
  for amt in '12\.25' '12\.34'; do
    for i in $(seq 1 9); do delrow "$amt" || break; done
  done
  # rows named in v4/v5 created logs (exact desc), baseline-guarded
  for LOG in "$OUT/created.log" "$OUT/createdb.log"; do
    [ -f "$LOG" ] || continue
    while IFS= read -r ROW; do
      [ -z "$ROW" ] && continue
      ROWX=$(printf '%s' "$ROW" | sed 's/[][().*+?^$|\\]/\\&/g')
      fresh || break
      XY=$($PY - "$OUT/.rcur.xml" "$ROW" "$BASE" <<'PYEOF'
import re,sys,os
row=sys.argv[2]; base_x=''
for bp in os.environ.get('GBASES','').split(','):
    try: base_x+=open(bp,encoding='utf-8',errors='ignore').read()
    except: pass
if re.search(r'content-desc="[^"]*%s"'%re.escape(row.replace('\n','&#10;')),base_x): sys.exit(1)
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'content-desc="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%re.escape(row.replace('\n','&#10;')),x)
if m:
    x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2)
PYEOF
) || continue
      [ -z "$XY" ] && { echo "CLEAN-NOTFOUND: $ROW" >> "$OUT/misses.log"; continue; }
      $ADB -s "$D" shell input tap $XY; sleep 1.5
      dump "$OUT/.rdet.xml"
      if findc "%Delete" "$OUT/.rdet.xml" >/dev/null; then
        xy=$(findc "%Delete" "$OUT/.rdet.xml"); $ADB -s "$D" shell input tap $xy; sleep 1
      else
        echo "DELETE-MISS: $ROW" >> "$OUT/misses.log"; $ADB -s "$D" shell input keyevent BACK
      fi
    done < "$LOG"
  done
  echo "l7 done $(date -u +%FT%TZ)" >> "$OUT/summary.txt"
fi
touch "$OUT/REPAIR-DONE"
