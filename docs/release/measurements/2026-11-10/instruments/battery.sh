#!/bin/bash
# Beta measurement battery — rc-polish audit leg runner (v2).
# Every tap preceded by a fresh uiautomator dump (device law); screenshots land
# OUTSIDE the device. Numbers are only valid beside this file's sha.
# Usage: battery.sh <device-serial> <tag>
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=$1; TAG=$2; PKG=dev.steiner.local_budget
OUT=/tmp/measure/$TAG; mkdir -p "$OUT"
PY=/workspace/Workspace/tools/python/bin/python3
now(){ date +%s%3N; }

dump(){ $ADB -s "$D" shell uiautomator dump /data/local/tmp/b.xml >/dev/null 2>&1; $ADB -s "$D" exec-out cat /data/local/tmp/b.xml > "$1" 2>/dev/null; }
# findc <name> <xml>: exact match, or prefix when name starts with '%'
findc(){ $PY - "$1" "$2" <<'PYEOF'
import re,sys
pat=sys.argv[1]
x=open(sys.argv[2],encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0)
    d=re.search(r'content-desc="([^"]*)"',n)
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
waitdesc(){ local name=$1 tmo=${2:-8} t0=$(now)
  while :; do
    dump "$OUT/.cur.xml"
    findc "$name" "$OUT/.cur.xml" >/dev/null && return 0
    [ $(( $(now)-t0 )) -gt $((tmo*1000)) ] && return 1
    sleep 0.35
  done
}
tapdesc(){ local name=$1 tmo=${2:-8} t0=$(now) xy
  while :; do
    dump "$OUT/.cur.xml"
    xy=$(findc "$name" "$OUT/.cur.xml") && { $ADB -s "$D" shell input tap $xy; return 0; }
    [ $(( $(now)-t0 )) -gt $((tmo*1000)) ] && { echo "MISS: $name" >> "$OUT/misses.log"; return 1; }
    sleep 0.35
  done
}
launch(){ $ADB -s "$D" shell am start -n $PKG/.MainActivity >/dev/null 2>&1; }
home(){ launch; sleep 1.2; waitdesc "Add receipt" 25; }
shot(){ $ADB -s "$D" exec-out screencap -p > "$OUT/$1.png"; }

echo "== battery $TAG on $D start $(date -u +%FT%TZ)" > "$OUT/summary.txt"

# ---------- L1 cold start x5 ----------
for i in 1 2 3 4 5; do
  $ADB -s "$D" shell am force-stop $PKG; sleep 3
  TT=""
  for try in 1 2; do
    TT=$($ADB -s "$D" shell am start -W -n $PKG/.MainActivity | tr -d '\r' | sed -n 's/^TotalTime: \([0-9]*\).*/\1/p')
    [ -n "$TT" ] && [ "$TT" != "0" ] && break
    $ADB -s "$D" shell am force-stop $PKG; sleep 2
  done
  echo "coldstart$i ${TT:-MISS} ms" >> "$OUT/summary.txt"
done
sleep 4

# ---------- L2 gfxinfo: QuickAdd x8 + ledger scroll ----------
$ADB -s "$D" shell dumpsys gfxinfo $PKG reset
for i in $(seq 1 8); do
  home || break
  tapdesc "Add receipt" 15   # open QuickAdd
  tapdesc $'1\n1' 8; tapdesc $'2\n2' 6; tapdesc $'.\n.' 6
  tapdesc $'2\n2' 6; tapdesc $'5\n5' 6; tapdesc "Food" 8
  tapdesc "Save" 8
done
for i in $(seq 1 12); do $ADB -s "$D" shell input swipe 540 1800 540 700 350; sleep 0.5; done
$ADB -s "$D" shell dumpsys gfxinfo $PKG framestats > "$OUT/gfx.txt" 2>&1
$ADB -s "$D" shell dumpsys gfxinfo $PKG | grep -E "Janky frames|Total frames" >> "$OUT/summary.txt"

# ---------- L3 gallery scan x10 ----------
: > "$OUT/scan.csv"
: > "$OUT/created.log"
for i in $(seq 0 9); do
  home || continue
  cp "$OUT/.cur.xml" "$OUT/.pre.xml" 2>/dev/null
  tapdesc "Scan a receipt" 15 || continue
  tapdesc "Photos" 10 || continue
  sleep 2; dump "$OUT/.pick.xml"
  XY=$($PY - "$OUT/.pick.xml" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
c=[]
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0)
    if not re.search(r'content-desc="Photo taken',n): continue
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
    if b:
        x1,y1,x2,y2=map(int,b.groups()); c.append((y1,x1,x2,y2))
if c:
    c.sort(); y1,x1,x2,y2=c[0]; print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
  [ -z "$XY" ] && { echo "scan$i PICK-MISS" >> "$OUT/scan.csv"; $ADB -s "$D" shell input keyevent BACK; continue; }
  T0=$(now); $ADB -s "$D" shell input tap $XY; sleep 1.5
  dump "$OUT/.pick2.xml"
  DX=$($PY - "$OUT/.pick2.xml" <<'PYEOF'
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
  tmo=$(( $(now)+60000 )); READY=0; MANUAL=0
  while :; do dump "$OUT/.rev.xml"
    grep -q 'content-desc="Save' "$OUT/.rev.xml" && { READY=1; break; }
    [ $(now) -gt $tmo ] && break; sleep 0.6; done
  R1=$(now)
  if [ $READY = 1 ]; then
    if grep -q 'No total found' "$OUT/.rev.xml"; then
      MANUAL=1
      tapdesc $'1\n1' 6; tapdesc $'2\n2' 6; tapdesc $'.\n.' 6; tapdesc $'3\n3' 6; tapdesc $'4\n4' 6
    fi
    tapdesc "Save" 10
  fi
  waitdesc "Add receipt" 25
  S1=$(now)
  echo "scan$i ready_ms=$((R1-T0)) total_ms=$((S1-T0)) manual_total=$MANUAL" >> "$OUT/scan.csv"
  dump "$OUT/.post.xml"
  $PY - "$OUT/.pre.xml" "$OUT/.post.xml" "$OUT/created.log" <<'PYEOF'
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
shot L3-final

# ---------- L4 camera launch x5 ----------
for i in 1 2 3 4 5; do
  home || continue
  tapdesc "Scan a receipt" 15 || continue
  T0=$(now); tapdesc "Camera" 10 || { echo "cam$i TAP-MISS" >> "$OUT/summary.txt"; continue; }
  tmo=$(( $(now)+15000 )); OK=0
  while :; do dump "$OUT/.cam.xml"; grep -q 'content-desc="Capture"' "$OUT/.cam.xml" && { OK=1; break; }
    [ $(now) -gt $tmo ] && break; sleep 0.15; done
  echo "camera$i $(( $(now)-T0 )) ms $([ $OK = 1 ] && echo preview-ok || echo TIMEOUT)" >> "$OUT/summary.txt"
  tapdesc "Close" 8; tapdesc "Scrim" 6 || $ADB -s "$D" shell input keyevent BACK
done

# ---------- L5 font scale 2.0 sweep ----------
$ADB -s "$D" shell settings put system font_scale 2.0
$ADB -s "$D" shell am force-stop $PKG; sleep 2; launch; sleep 6
dump "$OUT/h2.xml"; shot L5-home-2x
tapdesc "Add receipt" 20; sleep 1; dump "$OUT/qa2.xml"; shot L5-quickadd-2x
tapdesc "%Scrim" 6 || $ADB -s "$D" shell input keyevent BACK; sleep 1
tapdesc "Scan a receipt" 15; tapdesc "Photos" 10; sleep 2
XY=$(dump "$OUT/.pk2.xml"; $PY - "$OUT/.pk2.xml" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
c=[]
for m in re.finditer(r'<node[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*?/?>',x):
    x1,y1,x2,y2=map(int,m.groups())
    if x2-x1>150 and 150<y2-y1<700 and y1>260: c.append((y1,x1,x2-x1,y2-y1))
if c: c.sort(); y,x,w,h=c[0]; print(x+w//2,y+h//2)
PYEOF
)
[ -n "$XY" ] && { $ADB -s "$D" shell input tap $XY; sleep 25; dump "$OUT/rev2.xml"; shot L5-review-2x; }
tapdesc "%Scrim" 6 || true
$ADB -s "$D" shell settings put system font_scale 1.0
echo -n "font restored to " >> "$OUT/summary.txt"; $ADB -s "$D" shell settings get system font_scale >> "$OUT/summary.txt"

# ---------- L6 TalkBack semantic audit ----------
TB=$($ADB -s "$D" shell pm list packages | grep -ci talkback || true)
echo "talkback_installed=$TB" >> "$OUT/summary.txt"
if [ "$TB" != "0" ]; then
  TBPKG=$($ADB -s "$D" shell pm list packages | grep -i talkback | head -1 | sed 's/package://' | tr -d '\r')
  $ADB -s "$D" shell settings put secure enabled_accessibility_services "$TBPKG/.TalkBackService" 2>/dev/null
  $ADB -s "$D" shell settings put secure accessibility_enabled 1 2>/dev/null; sleep 5
  home; dump "$OUT/tb-home.xml"
  tapdesc "%Bills" 10;   dump "$OUT/tb-bills.xml"
  tapdesc "%Budgets" 10; dump "$OUT/tb-budgets.xml"
  home; tapdesc "Scan a receipt" 12; dump "$OUT/tb-scan.xml"
  tapdesc "%Scrim" 6 || true
  $ADB -s "$D" shell settings put secure enabled_accessibility_services "" 2>/dev/null
  $ADB -s "$D" shell settings put secure accessibility_enabled 0 2>/dev/null
  echo "talkback disabled again" >> "$OUT/summary.txt"
fi

# ---------- L7 cleanup: tonight's created rows ----------
for amt in "12\\.25" "12\\.34"; do
  for i in $(seq 1 8); do
    home
    XY=$($PY - "$OUT/.cur.xml" "$amt" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'content-desc="([^"]*%s[^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%sys.argv[2],x)
if m:
    x1,y1,x2,y2=map(int,m.groups()[1:5]); print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
    [ -z "$XY" ] && break
    $ADB -s "$D" shell input tap $XY; sleep 1.5
    tapdesc "%Delete" 6 || { echo "DELETE-MISS $amt $i" >> "$OUT/misses.log"; $ADB -s "$D" shell input keyevent BACK; }
    sleep 1
  done
done
# rows named in created.log (scan fixtures)
while IFS= read -r ROW; do
  [ -z "$ROW" ] && continue
  home || break
  XY=$($PY - "$OUT/.cur.xml" "$ROW" <<'PYEOF'
import re,sys
row=sys.argv[2].replace('\n','&#10;')
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'content-desc="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'%re.escape(row),x)
if m:
    x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2)
PYEOF
)
  [ -z "$XY" ] && { echo "CLEAN-MISS: $ROW" >> "$OUT/misses.log"; continue; }
  $ADB -s "$D" shell input tap $XY; sleep 1.5
  tapdesc "%Delete" 6 || { echo "DELETE-MISS: $ROW" >> "$OUT/misses.log"; $ADB -s "$D" shell input keyevent BACK; }
  sleep 1
done < "$OUT/created.log"

echo "== done $(date -u +%FT%TZ)" >> "$OUT/summary.txt"
touch "$OUT/DONE"
