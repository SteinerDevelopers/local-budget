#!/bin/bash
# l5c flip6: font 2.0 semantic dumps + trustworthy screenshots (device-file screencap)
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=192.168.1.50:41055; TAG=flip6; OUT=/tmp/measure/flip6
PKG=dev.steiner.local_budget; PICK=com.google.android.photopicker; TB=com.google.android.marvin.talkback
PY=/workspace/Workspace/tools/python/bin/python3
dump(){ $ADB -s $D shell uiautomator dump /data/local/tmp/f.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/f.xml > "$1" 2>/dev/null; }
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
wake(){ $ADB -s $D shell input keyevent KEYCODE_WAKEUP; sleep 1.2; }
shot(){ wake; $ADB -s $D shell screencap -p /data/local/tmp/s.png; $ADB -s $D exec-out cat /data/local/tmp/s.png > "$OUT/$1.png"; head -c 4 "$OUT/$1.png" | grep -q PNG && echo "png-ok $1" | tee -a "$OUT/summary.txt" || echo "PNG-CORRUPT $1" | tee -a "$OUT/summary.txt"; }
td(){ local n=$1 t=${2:-10} t0=$(date +%s%3N) xy
  wake
  while :; do dump "$OUT/.fcur.xml"
    xy=$(findc "$n" "$OUT/.fcur.xml") && { $ADB -s $D shell input tap $xy; return 0; }
    [ $(( $(date +%s%3N)-t0 )) -gt $((t*1000)) ] && { echo "MISS:$n" | tee -a "$OUT/misses.log"; return 1; }
    sleep 0.4; done
}
OLDTO=$($ADB -s $D shell settings get system screen_off_timeout | tr -d '\r')
$ADB -s $D shell settings put system screen_off_timeout 1800000
$ADB -s $D shell settings put system font_scale 2.0
$ADB -s $D shell am force-stop $TB; $ADB -s $D shell am force-stop $PICK; $ADB -s $D shell am force-stop $PKG
sleep 2; wake
$ADB -s $D shell am start -n $PKG/.MainActivity >/dev/null; sleep 5
dump "$OUT/c2-home.xml"; shot c2-home-2x
td "Add receipt" 15; sleep 1; dump "$OUT/c2-qa.xml"; shot c2-quickadd-2x
td "%Scrim" 8 || $ADB -s $D shell input keyevent BACK; sleep 1
td "Scan a receipt" 15; sleep 1; dump "$OUT/c2-scanmenu.xml"; shot c2-scanmenu-2x
td "Photos" 10; sleep 2; dump "$OUT/c2-pick.xml"; shot c2-pick-2x
# close picker without selecting
$ADB -s $D shell input keyevent BACK; sleep 1; $ADB -s $D shell input keyevent BACK
$ADB -s $D shell settings put system font_scale 1.0
$ADB -s $D shell settings put system screen_off_timeout "$OLDTO"
echo "l5c done $(date -u +%FT%TZ) font=$($ADB -s $D shell settings get system font_scale | tr -d '\r') timeout=$($ADB -s $D shell settings get system screen_off_timeout | tr -d '\r')" >> "$OUT/summary.txt"
touch "$OUT/L5C-DONE"
