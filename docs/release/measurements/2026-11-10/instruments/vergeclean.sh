#!/bin/bash
# VERGE ledger cleanup: delete every row whose desc contains $12.25/$12.34 (sentinels
# never present in baseline — grep-proven against /tmp/home.xml) via row -> Delete.
set -u
ADB=/workspace/Workspace/tools/android-sdk/platform-tools/adb
export HOME=/workspace/Workspace/tools/home
D=192.168.1.226:41283; PKG=dev.steiner.local_budget; OUT=/tmp/measure/verge
PY=/workspace/Workspace/tools/python/bin/python3
front(){ $ADB -s $D shell "dumpsys window 2>/dev/null | grep -m1 mCurrentFocus" | grep -c "$PKG"; }
dump(){ $ADB -s $D shell uiautomator dump /data/local/tmp/c.xml >/dev/null 2>&1; $ADB -s $D exec-out cat /data/local/tmp/c.xml > /tmp/c.xml 2>/dev/null; }
rowxy(){ $PY - "$1" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0); d=re.search(r'content-desc="([^"]*(?:12[.,]25|12[.,]34)[^"]*)"',n)
    if d and 'Today' in d.group(1):
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(1)
PYEOF
}
deldescxy(){ $PY - "$1" <<'PYEOF'
import re,sys
x=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<node[^>]*?/?>',x):
    n=m.group(0); d=re.search(r'content-desc="(Delete|delete)"',n)
    if d:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(1)
PYEOF
}
$ADB -s $D shell am force-stop com.google.android.photopicker; $ADB -s $D shell am force-stop com.google.android.marvin.talkback; $ADB -s $D shell am force-stop $PKG
sleep 2; $ADB -s $D shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for t in $(seq 1 30); do sleep 1.5; [ "$(front)" = 1 ] && break; done
DELETED=0; STALL=0
for it in $(seq 1 40); do
  dump
  XY=$(rowxy /tmp/c.xml) || XY=""
  if [ -z "$XY" ]; then
    # maybe below the fold: scroll list up (swipe up), re-check
    $ADB -s $D shell input swipe 360 1100 360 500 300; sleep 1; dump
    XY=$(rowxy /tmp/c.xml) || XY=""
    if [ -z "$XY" ]; then STALL=$((STALL+1)); [ $STALL -ge 4 ] && break; continue; fi
  fi
  STALL=0
  $ADB -s $D shell input tap $XY; sleep 1.5
  dump
  DXY=$(deldescxy /tmp/c.xml) || DXY=""
  if [ -z "$DXY" ]; then echo "DELETE-MISS at $XY" >> $OUT/misses.log; $ADB -s $D shell input keyevent BACK; sleep 1; continue; fi
  $ADB -s $D shell input tap $DXY; sleep 1.2; DELETED=$((DELETED+1))
done
echo "verge cleanup deleted=$DELETED $(date -u +%FT%TZ)" | tee -a $OUT/summary.txt
# verify: pull DB, count sentinel amounts
$ADB -s $D exec-out "run-as $PKG cat app_flutter/localbudget.sqlite" > /tmp/verge2.db 2>/dev/null
$PY - <<'PYEOF'
import sqlite3
try:
    c=sqlite3.connect('/tmp/verge2.db')
    n=list(c.execute("select count(*) from transactions where amount_minor in (1225,1234)"))[0][0]
    t=list(c.execute("select count(*) from transactions"))[0][0]
    print(f"sentinel rows remaining: {n} (total txns {t})")
except Exception as e: print("DB ERR", e)
PYEOF
