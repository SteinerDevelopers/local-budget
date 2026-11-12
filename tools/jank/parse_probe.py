#!/usr/bin/env python3
"""parse_probe.py — summarize a probe.sh capture dir.

Two independent attributions (report BOTH; disagreement = measurement bug):
1. framestats: Janky% + p90/p99 of TotalDuration (Plan+Issue split tells
   UI-thread vs RenderThread at the frame level).
2. perfetto trace (if trace_processor available): time sliced by thread name
   — '1.ui' vs '1.raster' — from the atrace frame slices.
Exit 0 always; advisory output.
"""
import re, sys, os, statistics as st

def pct(vals, q):
    if not vals: return 0
    vals = sorted(vals); i = min(int(round(q*(len(vals)-1))), len(vals)-1)
    return vals[i]

def framestats(path):
    plan, issue, total = [], [], []
    for line in open(path, errors='ignore'):
        m = re.match(r'\s*\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+', line)
        if m:
            p, i, t = map(int, m.groups())
            if 0 < t < 5000:
                plan.append(p); issue.append(i); total.append(t)
    if not total: return None
    return dict(n=len(total), p90=pct(total,.90), p99=pct(total,.99),
                p90_plan=pct(plan,.90), p90_issue=pct(issue,.90),
                med_plan=st.median(plan), med_issue=st.median(issue))

def main(outdir):
    fs = None
    fsp = os.path.join(outdir, 'framestats.txt')
    if os.path.exists(fsp): fs = framestats(fsp)
    print("== framestats (gfxinfo)")
    if os.environ.get('PARSE_STRICT') and fs is None:
        sys.exit(2)   # opt-in strict mode for CI-like use; advisory default exits 0
    if fs:
        print(f"  frames={fs['n']} p90={fs['p90']}ms p99={fs['p99']}ms")
        print(f"  p90 split: plan(UI)={fs['p90_plan']}ms issue(RT)={fs['p90_issue']}ms")
        print(f"  median split: plan(UI)={fs['med_plan']}ms issue(RT)={fs['med_issue']}ms")
        dom = 'UI-thread' if fs['p90_plan'] >= fs['p90_issue'] else 'RenderThread'
        print(f"  frame-level attribution: {dom} dominates")
    else:
        print("  (no framestats rows — was the app foregrounded during capture?)")
    print("== perfetto thread slices")
    print("  (offline step: trace_processor -q 'select thread.name, sum(dur) "
          "from thread_slice group by 1 order by 2 desc limit 10' "
          f"{os.path.join(outdir,'trace.perfetto-trace')} — run on the "
          "analysis box; 1.ui vs 1.raster rows are the §A verdict line)")
    # compare vs frozen baseline
    try:
        base = float(os.environ.get('BASELINE_P99', '106'))
        if fs:
            print(f"== vs frozen baseline (VERGE SHEET p99 {base}ms): "
                  f"{fs['p99']}ms — {'IMPROVED' if fs['p99'] < base*0.6 else 'not decisive'}")
    except Exception: pass

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
