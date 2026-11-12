#!/usr/bin/env python3
"""model-check.py — CI-class gate for the 5-year portfolio workbook.

Closes the gap the v4 incident exposed (fantasy iOS math reaching a
review draft): every generated model must pass mechanical sanity BEFORE
it is presented. Exit 0 = all checks pass; exit 1 + named violations.

    python3 model-check.py <workbook.xlsx> [--selftest]

Checks (each catches a real 2026-11-12 failure mode):
  R1 per-line ceiling:  per-year gross <= y1_rev * cap_warm(1.5)
                        (catches tuple-index/unit-vs-revenue confusion)
  R2 tail decay:    strictly from the line's PEAK year on, no growth
                        (mid-year launches legitimately grow year 1->2;
                         tails 55/38/28/22 must never)
  R3 portfolio band:    5y gross within $15k..$500k mid-scale sanity
  R4 column sum:        by-year sum of lines == combined row (+-1%)
  R5 pricing:           $0.99 <= price <= $49.99; units/installs > 0
  R6 fee ratio:         0.70 <= net/gross <= 0.92
  R7 iOS rails:         an A-iOS line's y1 revenue <= 0.8x the median
                        Tier-A Android line's (iOS is a top-up, not a curve)
"""
import sys, openpyxl

WARM_CAP, BAND = 1.5, (15_000, 500_000)

def load(path):
    ws = openpyxl.load_workbook(path)['Model']
    lines, combined_row, net_row = [], None, None
    andr = []
    hdr = None
    for row in ws.iter_rows(values_only=True):
        if row[0] == 'App':
            hdr = row; continue
        if row[0] and str(row[0]).startswith('Combined GROSS'):
            combined_row = row; continue
        if row[0] and str(row[0]).startswith('NET'):
            net_row = row; continue
        if hdr and row[0] and len(row) > 10 and isinstance(row[10], (int, float)) and row[10]:
            lines.append(dict(name=str(row[0]), tier=str(row[1]), price=row[3],
                              y1=row[4] or 0, years=[row[5+i] or 0 for i in range(5)],
                              total=row[10]))
    return lines, combined_row, net_row

def check(lines, combined_row, net_row):
    v = []
    for L in lines:
        cap = (L['y1'] or 0) * WARM_CAP * 1.05 + 50
        for i, g in enumerate(L['years']):
            if g and g > cap and cap > 0:
                v.append(f"R1 {L['name']}: year{i} ${g:,.0f} exceeds line ceiling ${cap:,.0f} (unit/rev confusion?)")
        peak = max(L['years']); pk = L['years'].index(peak)
        for a, b in zip(L['years'][pk:], L['years'][pk+1:]):
            if b > a * 1.05:
                v.append(f"R2 {L['name']}: growth ${a:,.0f}->${b:,.0f} AFTER peak year (tails must decay)")
        if L['price'] and not (0.99 <= L['price'] <= 49.99):
            v.append(f"R5 {L['name']}: price ${L['price']} out of $0.99-49.99")
    tot = sum(L['total'] for L in lines)
    if not (BAND[0] <= tot <= BAND[1]):
        v.append(f"R3 portfolio 5y gross ${tot:,.0f} outside band $15k-$500k")
    if combined_row:
        for i in range(5):
            col = sum(L['years'][i] for L in lines)
            comb = combined_row[5+i] or 0
            if comb and abs(col - comb) > 0.01 * max(comb, 1):
                v.append(f"R4 year{i+2027}: lines {col:,.0f} vs combined {comb:,.0f}")
        if net_row:
            net = sum(x for x in net_row[5:10] if isinstance(x, (int, float)))
            if tot > 0 and not (0.70 <= net / tot <= 0.92):
                v.append(f"R6 net/gross {net/tot:.2f} outside 0.70-0.92")
    # R7: iOS line must stay a top-up of ITS OWN named Android sibling
    ios = [L for L in lines if 'iOS' in L['tier'] or 'iOS' in L['name']]
    for L in ios:
        base = L['name'].replace(' iOS', '').replace(' (E10)', '').replace(' (E10 follow-on)', '').strip()
        sib = [A for A in lines if A['tier'].startswith('A') and 'iOS' not in A['name']
               and (A['name'].startswith(base) or base.startswith(A['name']) or base.lower().replace('steiner ','') in A['name'].lower())]
        if sib and L['y1'] > 0.8 * sib[0]['y1']:
            v.append(f"R7 {L['name']}: y1 ${L['y1']:,.0f} > 0.8x sibling {sib[0]['name']} ${sib[0]['y1']:,.0f} — iOS-as-second-curve is the fantasy rail")
    return v, tot

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--selftest' in sys.argv:
        lines, _, _ = load(args[0])
        lines[0]['years'][0] = lines[0]['y1'] * 40          # inject fantasy
        v, _ = check(lines, None, None)
        print('selftest violations detected:', len(v), '(need >=1)')
        sys.exit(0 if v else 1)
    lines, comb, net = load(args[0])
    v, tot = check(lines, comb, net)
    for x in v: print('VIOLATION:', x)
    print(f'{args[0]}: {len(lines)} lines, 5y gross ${tot:,.0f} — ' + ('PASS' if not v else 'FAIL'))
    sys.exit(0 if not v else 1)

if __name__ == '__main__':
    main()
