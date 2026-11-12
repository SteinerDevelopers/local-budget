import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

# ---- measured-velocity mechanics ----
# Evidence 2026-11-12: Tier A chassis build ~1 wk (Vault V1-V7 in 48h, kit +3d);
# Tier B build ~2 wk (novel API surface); hardening 1 wk (soak+receipts); beta 3-4 wk;
# GA-PREP IS SERIALIZED (one owner: keystore/console/filings/store-review attention).
# => max ~6 GAs/yr raw, ~5-6 realistic; attack pace holds UNTIL the upkeep gauge says stop.
SCHED = [ # name, tier, launch_year, launch_qtr, price, y1_inst, conv
 ("Local Budget","A",2026,4,5.99,30000,0.016),
 ("Steiner Vault","A",2027,1,9.99,31000,0.019),
 ("Pantry & Expiry","A",2027,2,6.99,22000,0.018),
 ("NAS Companion","B",2027,3,11.99,12000,0.028),
 ("Encrypted Journal","A",2027,4,9.99,20000,0.020),
 ("Media Server Companion","B",2028,1,9.99,13000,0.030),
 ("Home Automation Companion","B",2028,2,10.99,11000,0.028),
 ("Family Board (LAN/p2p)","A",2028,3,8.99,16000,0.015),
 ("Personal CRM-lite","A",2028,4,7.99,12000,0.016),
 ("Photo Server Client","B",2029,1,9.99,10000,0.028),
 ("Paperless Client","B",2029,3,9.99,8000,0.030),
 ("Sync Front-end","B",2030,1,8.99,9000,0.026),
 ("RSS Reader","B",2030,3,6.99,10000,0.024),
 ("Digital Legacy","A",2031,1,12.99,10000,0.016),
 ("Next-in-line client","B",2031,3,8.99,7000,0.026),
]
# iOS paid-downloads for a solo dev with no paid UA: calibrated as a share of the
# ANDROID app's same-window paid conversion, not as absolute installs. Budget iOS =
# 45% of Budget's Y1 Android paid units (iOS share of our reachable privacy audience
# is smaller, and paid-up-front converts far below a free app's unlock rate).
IOS = [
 ("Steiner Budget iOS (E10)","A-iOS",2027,3,6.99,0.45,"Local Budget"),
 ("Steiner Vault iOS (E10 follow-on)","A-iOS",2028,3,11.99,0.45,"Steiner Vault"),
]
TAIL=[0.55,0.38,0.28,0.22]; WARM=0.10; CAP_WARM=1.5
FEE,FIXED=0.15,400; YEARS=list(range(2027,2032))
DILUTION_AFTER=10; DILUTE=0.85   # buyer-attention dilution after 10 live products

def compute():
    yrs={y:0.0 for y in YEARS}; tot=0.0; rows=[]
    android_paid={s[0]: s[5]*s[6]*s[4] for s in SCHED}  # inst*conv*price   # y1_inst * conv * price
    for n,(name,tier,ly,q,price,share,parent) in enumerate(IOS, len(SCHED)+1):
        # iOS paid-downloads = share x (android sibling's paid revenue / that app's price)
        psib=[s for s in SCHED if s[0]==parent][0]
        units_y1 = share * (psib[5]*psib[6]) * (psib[4]/price)   # paid units, price-adjusted (inst*conv)   # unit-for-unit, price-adjusted
        warm=min(1+WARM*0.5*(n-1),1.25)   # iOS carries only HALF the brand lift: separate store, separate reviews
        g_by_y={}
        for y in YEARS:
            k=y-ly
            if k<0: continue
            frac=(5-q)/4 if k==0 else (TAIL[k-1] if k-1<len(TAIL) else 0)
            g=units_y1*price*warm*frac; g_by_y[y]=g; yrs[y]+=g; tot+=g
        rows.append((name,tier,f"{ly} Q{q}",price,round(units_y1*price*warm),{y:round(g_by_y.get(y,0)) for y in YEARS},round(sum(g_by_y.values()))))
    for n,(name,tier,ly,q,price,inst,conv) in enumerate(SCHED,1):
        warm=min(1+WARM*(n-1),CAP_WARM); dil=1.0 if n<=DILUTION_AFTER else DILUTE
        g_by_y={}
        for y in YEARS:
            k=y-ly
            if k<0: continue
            frac=(0.25 if ly==2026 else (5-q)/4) if k==0 else (TAIL[k-1] if k-1<len(TAIL) else 0)
            g=inst*conv*price*warm*dil*frac; g_by_y[y]=g; yrs[y]+=g; tot+=g
        rows.append((name,tier,f"{ly} Q{q}",price,round(inst*conv*price*warm*dil),{y:round(g_by_y.get(y,0)) for y in YEARS},round(sum(g_by_y.values()))))
    return yrs,tot,rows

wb=openpyxl.Workbook(); hdr=Font(bold=True,color="FFFFFF"); hfill=PatternFill("solid",fgColor="2F5233")
def sh(ws,row,n):
    for c in range(1,n+1):
        x=ws.cell(row=row,column=c); x.font=hdr; x.fill=hfill

ws=wb.active; ws.title="README"; ws.column_dimensions['A'].width=112
LINES=[
 "STEINER DEVELOPERS — 5-YEAR MODEL v4: + iOS (E10-conditional), Apple Dev $99/yr 2027+, Mac mini Dec-26 capex",
 "iOS ADDITION (owner request 2026-11-12): Apple Dev Program $99/yr enters the NET line from 2027; Mac mini (M3/M4, ~$700 mid) is Dec-2026 one-time capex, outside the 2027-31 columns (stated on the NET row). iOS revenue modelled as a SHARE of the Android sibling's paid conversion (45%), not absolute installs — because we have no paid user acquisition and paid-up-front converts well below a free app's unlock rate. Brand lift halved for iOS (separate store, separate review base, no cross-store review inheritance). Y1 Budget iOS lands ~215 paid downloads; the honest read: iOS is a margin top-up, not a second curve. BOTH iOS LINES ARE E10-CONDITIONAL (decision 11 — owner gate): strip them and v4 = v3 minus $99/yr. Built 2026-11-12. Replaces v2's per-quarter abstraction with the velocities measured from Budget (357 commits/10 active days public era; features done, release tail Nov 9-16+) and Vault (V1-V7 epics in 48 h, 0.9.0 kit +3 days, 137 commits/6 days) — sprint-condition ceilings discounted 1.5-2x for ordinary weeks.",
 "",
 "MECHANICS (measured, not assumed)",
 "• Tier A build ≈ 1 chassis-week; Tier B build ≈ 2 weeks (novel API surface). Hardening ≈ 1 week (soak + receipts, owner-refuses-to-shorten). Beta 3-4 weeks, OVERLAPPABLE with next app's build.",
 "• THE SERIAL RESOURCE IS GA-PREP, NOT BUILDING: keystore, store console, filings, compliance responses — one owner, one at a time. Ceiling ≈ 6 GAs/yr raw, 5-6 realistic. Model schedules 5 in 2027, 4 in 2028, then gauge-gated.",
 "• Warm-brand lift +10%/prior ship (cap +50%). Buyer-attention dilution x0.85 after 10 live products. Tail decay 55/38/28/22%. Net = gross x0.85 − $400/yr. Scenarios: pess x0.5, opt x1.9.",
 "",
 "THE UPKEEP GAUGE (sheet 'Upkeep Gauge') — the governance upgrade this version exists for",
 "The v2 portfolio cap (~11-12 apps) was MY estimate. v3 makes it YOUR DATA: every app's maintenance is measured in DEV-HOURS PER WEEK at M2 and M3 months post-GA (launch turbulence excluded at M1), in five buckets: OS/API/store-compliance fixes; support tickets; security-response obligations; release/receipt chores; review replies.",
 "CAP RULE: capacity C is set by the owner in one place (default 15 h/wk — the sustainable slice of evenings after a full-time job). At every GA gate: portfolio_annuity = sum of the latest MEASURED value per app (projected values only for apps younger than M2). If projected_annuity + new_app_estimate > C, the next GA-PREP PAUSES — the next app keeps being built and beta'd (builds don't cost upkeep until GA), but it does not cross the release line until the gauge says there is room. If measurements lapse for an app, that app keeps its last reading (lapse never lowers the annuity). The gauge is the only thing that may raise C — no roadmap ambition ever does.",
 "First real datapoints land early 2027 (Budget M2 ≈ Feb-2027 GA +2mo) and every gate thereafter is data-gated. The model below is the plan the gauge supervises, not a promise the gauge must agree with.",
]
for i,l in enumerate(LINES,1): ws.cell(row=i,column=1,value=l).alignment=Alignment(wrap_text=True)
ws.cell(row=1,column=1).font=Font(bold=True,size=14)

ws=wb.create_sheet("Model")
yrs,tot,rows=compute()
cols=["App","Tier","GA","Price $","Y1 gross (mid)"]+[str(y) for y in YEARS]+["5yr total"]
for c,h in enumerate(cols,1): ws.cell(row=1,column=c,value=h)
sh(ws,1,len(cols)); r=2
for (name,tier,ly,price,y1,gy,t) in rows:
    ws.cell(row=r,column=1,value=name); ws.cell(row=r,column=2,value=tier); ws.cell(row=r,column=3,value=ly)
    ws.cell(row=r,column=4,value=price).number_format='$#,##0.00'; ws.cell(row=r,column=5,value=y1).number_format='$#,##0'
    for c,y in enumerate(YEARS,6): ws.cell(row=r,column=c,value=gy[y]).number_format='$#,##0'
    ws.cell(row=r,column=11,value=t).number_format='$#,##0'; ws.cell(row=r,column=11).font=Font(bold=True); r+=1
ws.cell(row=r,column=1,value="Combined GROSS (mid)").font=Font(bold=True)
for c,y in enumerate(YEARS,6): ws.cell(row=r,column=c,value=round(yrs[y])).number_format='$#,##0'
ws.cell(row=r,column=11,value=round(tot)).number_format='$#,##0'; r+=1
ws.cell(row=r,column=1,value="NET (x0.85 fee - $400 fixed - $99 Apple Dev from 2027; Mac mini ~$700 Dec-26 capex outside these columns)")
nt=0
for c,y in enumerate(YEARS,6):
    n_=max(0,yrs[y]*0.85-FIXED-99); ws.cell(row=r,column=c,value=round(n_)).number_format='$#,##0'; nt+=n_
ws.cell(row=r,column=11,value=round(nt)).number_format='$#,##0'; ws.cell(row=r,column=11).font=Font(bold=True); r+=1
ws.cell(row=r,column=1,value=f"scenarios: pess net ≈ ${nt*0.5:,.0f} · opt net ≈ ${nt*1.9:,.0f}").font=Font(italic=True)
ws.column_dimensions['A'].width=32
for c in range(2,12): ws.column_dimensions[get_column_letter(c)].width=11

ws=wb.create_sheet("Upkeep Gauge")
cols=["App","GA date","M2 due (start logging)","M3 due","Latest measured h/wk","Bucket detail (OS/compliance · support · security · release · reviews)","Gate status"]
for c,h in enumerate(cols,1): ws.cell(row=1,column=c,value=h)
sh(ws,1,len(cols))
proj={"Local Budget":2.0,"Steiner Vault":1.5,"Pantry & Expiry":1.2,"NAS Companion":1.0,"Encrypted Journal":1.2}
r=2
for (name,tier,ly,q,price,inst,conv) in SCHED:
    ws.cell(row=r,column=1,value=name); ws.cell(row=r,column=2,value=f"{ly} Q{q}")
    ws.cell(row=r,column=3,value="+2 mo"); ws.cell(row=r,column=4,value="+3 mo")
    v=proj.get(name)
    ws.cell(row=r,column=5,value=v if v else "pending M2")
    ws.cell(row=r,column=6,value="log via weekly tick, 5 buckets, owner's own time only")
    ws.cell(row=r,column=7,value="PROJECTED (pre-M2)" if v else "gauge-gated")
    r+=1
r+=1
ws.cell(row=r,column=1,value="CAPACITY C (owner-set, one number): 15 h/wk default").font=Font(bold=True); r+=1
ws.cell(row=r,column=1,value="PROJECTED ANNUITY CHECK (using projections above; replaced by measurements as they land):"); r+=1
checks=[(5,6.9,"2028 gate"),(9,11.0,"2029 gate"),(12,14.1,"2030 gate"),(15,16.5,"2031 gate")]
for n,a,lab in checks:
    ws.cell(row=r,column=1,value=f"{lab}: {n} apps × avg ≈ {a/n:.1f} h/wk → annuity ≈ {a:.1f} h/wk vs C=15")
    ws.cell(row=r,column=2,value="GATE OPEN" if a<=15 else "GATE CLOSED at this projection — last two apps wait for measured relief or a raised C")
    r+=1
r+=1
ws.cell(row=r,column=1,value="The projected relief that keeps the 2031 gate near-open is chassis amortization: one OS/API break patched in the shared packages serves every app. If M2/M3 data shows less relief than projected (annuity per app stays >1.3 h/wk), the cap is ~11-12 apps and the tail of this schedule simply doesn't ship — which is the correct outcome, discovered by arithmetic instead of by burnout.").alignment=Alignment(wrap_text=True)
ws.merge_cells(start_row=r,start_column=1,end_row=r+2,end_column=7)
for c,w in zip("ABCDEFG",(26,12,20,10,20,52,44)): ws.column_dimensions[c].width=w

out="/workspace/Workspace/steiner-portfolio-5yr-model-v4-ios-2026-11-12.xlsx"
wb.save(out); print("saved",out)
print("gross mid",f"${tot:,.0f}","net ≈",f"${nt:,.0f}","| by year:",{y:int(v) for y,v in yrs.items()})
