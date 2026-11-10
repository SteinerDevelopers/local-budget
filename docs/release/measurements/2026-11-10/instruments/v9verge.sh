#!/bin/bash
# v8 verge: THE proven manual polling pattern. One dump per poll, 1.5s cadence.
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=192.168.1.226:41283; OUT=/tmp/measure/verge
PY=/workspace/Workspace/tools/python/bin/python3
PKG=dev.steiner.local_budget; PICK=com.google.android.photopicker; TB=com.google.android.marvin.talkback
now(){ date +%s%3N; }
killall3(){ $ADB -s $D shell am force-stop $TB; $ADB -s $D shell am force-stop $PICK; $ADB -s $D shell am force-stop $PKG; }
# poll for desc presence after launch; echoes ms until first match (or TIMEOUT)
wait_home(){ local t0=$(now) lim=${1:-70}
  while :; do
    sleep 1.5
    $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1
    $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.z.xml" 2>/dev/null
    grep -q 'content-desc="Add receipt"' "$OUT/.z.xml" && { echo $(( $(now)-t0 )); return 0; }
    [ $(( $(now)-t0 )) -gt $((lim*1000)) ] && { echo TIMEOUT; return 1; }
  done
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
# generic poll+tap: waits for node via repeated dumps, then taps it
pt(){ local name=$1 lim=${2:-30} xy t0=$(now)
  while :; do
    [ $(wc -c < "$OUT/.z.xml" 2>/dev/null || echo 0) -gt 2000 ] || { $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.z.xml" 2>/dev/null; }
    xy=$(findc "$name" "$OUT/.z.xml") && { $ADB -s $D shell input tap $xy; : > "$OUT/.z.xml"; return 0; }
    : > "$OUT/.z.xml"
    [ $(( $(now)-t0 )) -gt $((lim*1000)) ] && { echo "MISS:$name" | tee -a "$OUT/misses.log"; return 1; }
    sleep 1.5
  done
}
wd2(){ local name=$1 lim=${2:-15} t0=$(now)
  while :; do
    $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.zw.xml" 2>/dev/null
    findc "$name" "$OUT/.zw.xml" >/dev/null && return 0
    [ $(( $(now)-t0 )) -gt $((lim*1000)) ] && return 1
    sleep 1.2
  done
}
fresh(){ killall3; sleep 2.5; $ADB -s "$D" shell am start -n $PKG/.MainActivity >/dev/null 2>&1; local r; r=$(wait_home 70); [ "$r" = TIMEOUT ] && return 1; return 0; }

echo "== v8 start $(date -u +%FT%TZ)" >> "$OUT/summary.txt"
# : > "$OUT/coldstart_e.csv"  # cold already banked
for i in 0; do killall3; sleep 3; $ADB -s $D shell am start -n $PKG/.MainActivity >/dev/null 2>&1; r=$(wait_home 70); echo "cold$i home_visible_ms=$r" >> "$OUT/coldstart_e.csv"; done

: > "$OUT/scan_e.csv"; : > "$OUT/created_e.log"
for i in $(seq 0 9); do
  fresh || { echo "scan$i FRESH-FAIL" >> "$OUT/scan_e.csv"; continue; }
  cp "$OUT/.z.xml" "$OUT/.zpre.xml" 2>/dev/null
  PT=0
  for try in 1 2 3; do
    pt "Scan a receipt" 20 || { echo "scan$i SCAN-MISS" >> "$OUT/scan_e.csv"; PT=9; break; }
    if pt "Photos" 12; then PT=1; break; fi
    sleep 1
  done
  [ $PT != 1 ] && { [ $PT != 9 ] && echo "scan$i PHOTOS-MISS" >> "$OUT/scan_e.csv"; continue; }
  sleep 2; $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.zpick.xml" 2>/dev/null
  XY=$($PY - "$OUT/.zpick.xml" "$i" <<'PYEOF'
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
  [ -z "$XY" ] && { echo "scan$i PICK-MISS" >> "$OUT/scan_e.csv"; continue; }
  T0=$(now); $ADB -s $D shell input tap $XY; sleep 2
  $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.zpick2.xml" 2>/dev/null
  DX=$($PY - "$OUT/.zpick2.xml" <<'PYEOF'
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
  [ -n "$DX" ] && $ADB -s $D shell input tap $DX
  tmo=$(( $(now)+90000 )); READY=0; MANUAL=0
  while :; do
    sleep 1.2; $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.zrev.xml" 2>/dev/null
    grep -q 'content-desc="Save' "$OUT/.zrev.xml" && { READY=1; break; }
    [ $(now) -gt $tmo ] && break
  done
  R1=$(now)
  if [ $READY = 1 ]; then
    if grep -q 'No total found' "$OUT/.zrev.xml"; then
      MANUAL=1; pt "%Amount" 15
      pt $'1\n1' 12; pt $'2\n2' 12; pt $'.\n.' 12; pt $'3\n3' 12; pt $'4\n4' 12
    fi
    pt "Food" 15; pt "Save" 15
  fi
  SAVED=0
  tt=$(now)
  while :; do sleep 1.5; $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.z.xml" 2>/dev/null
    grep -q 'content-desc="Add receipt"' "$OUT/.z.xml" && { SAVED=1; break; }
    [ $(( $(now)-tt )) -gt 60000 ] && break
  done
  S1=$(now)
  echo "scan$i ready_ms=$((R1-T0)) total_ms=$((S1-T0)) manual=$MANUAL saved=$SAVED" >> "$OUT/scan_e.csv"
  cp "$OUT/.z.xml" "$OUT/.zpost.xml" 2>/dev/null
  $PY - "$OUT/.zpre.xml" "$OUT/.zpost.xml" "$OUT/created_e.log" <<'PYEOF'
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
for n in sorted(b-a): open(out,'a').write(n+'\n')
PYEOF
done

: > "$OUT/camera_e.csv"
for i in 1 2 3 4 5; do
  fresh || { echo "cam$i FRESH-FAIL" >> "$OUT/camera_e.csv"; continue; }
  CT=0
  for try in 1 2 3; do
    pt "Scan a receipt" 20 || { echo "cam$i SCAN-MISS" >> "$OUT/camera_e.csv"; CT=9; break; }
    if wd2 "Camera" 12; then CT=1; break; fi
    sleep 1
  done
  [ $CT != 1 ] && { [ $CT != 9 ] && echo "cam$i CHOOSE-MISS" >> "$OUT/camera_e.csv"; continue; }
  T0=$(now)
  pt "Camera" 20 || { echo "cam$i TAP-MISS" >> "$OUT/camera_e.csv"; continue; }
  tmo=$(( $(now)+25000 )); OK=0
  while :; do sleep 1; $ADB -s $D shell uiautomator dump /data/local/tmp/x.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/x.xml > "$OUT/.zcam.xml" 2>/dev/null
    grep -q 'content-desc="Capture"' "$OUT/.zcam.xml" && { OK=1; break; }
    [ $(now) -gt $tmo ] && break
  done
  echo "cam$i $(( $(now)-T0 )) ms $([ $OK = 1 ] && echo ok || echo TIMEOUT-unverifiable-no-idle)" >> "$OUT/camera_e.csv"
  $ADB -s $D shell input keyevent BACK; sleep 1
done
echo "== v8 done $(date -u +%FT%TZ)" >> "$OUT/summary.txt"
touch "$OUT/V9-DONE"
