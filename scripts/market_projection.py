#!/usr/bin/env python3
"""Steiner Budget — 12-month revenue projection instrument (2026-11-10).

Every constant traces to docs/market/2026-11-10-market-analysis.md (input
table: source URL + measured/estimated mark per number). Marketing-limitation
constraints baked into the shape: Play-only, US storefront only, zero ad
spend, zero telemetry (organic curve only — no re-engagement exists),
revenue = Pro sibling listing + coffee-tip IAPs, monetization opens only
after the business-account migration (docs/release/internal-beta-runbook.md).

Run: python3 scripts/market_projection.py
"""

MONTHS = ["Dec-26", "Jan-27", "Feb-27", "Mar-27", "Apr-27", "May-27",
          "Jun-27", "Jul-27", "Aug-27", "Sep-27", "Oct-27", "Nov-27"]

# Scenario shapes: free-listing installs per month after production opens.
# Low: quiet launch, no event, late migration. Base: steady Play-search
# compounding (store search ~58 % of Play discovery). Spike: one community
# event (Show HN / r/privacy / listicle) with a velocity halo afterwards.
SCENARIOS = {
    "low": dict(prod_from="Mar-27",
                curve={"Mar-27": 110, "Apr-27": 120, "May-27": 130, "Jun-27": 140,
                       "Jul-27": 155, "Aug-27": 170, "Sep-27": 185, "Oct-27": 200,
                       "Nov-27": 215},
                spike=None, halo=0.0, pro_rate=0.004, tips_gross=70),
    "base": dict(prod_from="Mar-27",
                 curve={"Mar-27": 150, "Apr-27": 220, "May-27": 300, "Jun-27": 380,
                        "Jul-27": 460, "Aug-27": 540, "Sep-27": 620, "Oct-27": 700,
                        "Nov-27": 780},
                 spike=None, halo=0.0, pro_rate=0.008, tips_gross=180),
    "spike": dict(prod_from="Jan-27",
                  curve={"Jan-27": 220, "Feb-27": 280, "Mar-27": 340, "Apr-27": 400,
                         "May-27": 460, "Jun-27": 520, "Jul-27": 580, "Aug-27": 640,
                         "Sep-27": 700, "Oct-27": 760, "Nov-27": 820},
                  spike=("May-27", 2500), halo=0.40, pro_rate=0.014,
                  tips_gross=350),
}

# iOS activation (decision 11): low = owner holds (trigger legs unmet);
# base = month-6 decision, M4 phase (+3-5 wk) lands Sep-27; spike = trigger
# fires on the >=10-sales leg around May, iOS live Jul-27. Prices per
# docs/pricing.md iOS ruling (11.99-12.99); low end used.
IOS = {
    "low": None,
    "base": dict(months=["Sep-27", "Oct-27", "Nov-27"],
                 installs=[120, 180, 240], conv=0.010, price=11.99),
    "spike": dict(months=["Jul-27", "Aug-27", "Sep-27", "Oct-27", "Nov-27"],
                  installs=[220, 320, 400, 460, 520], conv=0.015, price=11.99),
}

PRICE = 9.99          # owner ruling 2026-11-08 (docs/pricing.md)
PLAY_CUT = 0.15       # Play 15 % tier below $1 M/yr
APPLE_CUT = 0.15      # App Store small-business program
REFUNDS = 0.08        # ASSUMED — no benchmark found; see doc input table
ELASTICITY = -1.5     # mid of measured -1..-4 band (IJRM 2023)


def project() -> None:
    for name, sc in SCENARIOS.items():
        open_i = MONTHS.index(sc["prod_from"])
        cum, sales_n, android_net = 0, 0, 0.0
        unit = PRICE * (1 - PLAY_CUT) * (1 - REFUNDS)
        rows = []
        for i, m in enumerate(MONTHS):
            inst = sc["curve"].get(m, 0)
            if sc["spike"] and m == sc["spike"][0]:
                inst += sc["spike"][1]
            elif sc["spike"] and i > MONTHS.index(sc["spike"][0]):
                inst = int(inst * (1 + sc["halo"]))
            cum += inst
            # Pro sales from the month's cohort at the sibling ratio;
            # consideration lag folded in by charging half a month (E).
            s = round(inst * sc["pro_rate"])
            sales_n += s
            android_net += s * unit
            rows.append((m, inst, cum, s))

        ios_net, ios_note = 0.0, "no iOS go (owner holds; trigger legs unmet)"
        cfg = IOS[name]
        if cfg:
            iunit = cfg["price"] * (1 - APPLE_CUT) * (1 - REFUNDS)
            ios_net = sum(n * cfg["conv"] * iunit for n in cfg["installs"])
            ios_note = (f"iOS {cfg['months'][0]}+ ({sum(cfg['installs'])} "
                        f"installs, {cfg['conv']:.1%} conv)")
        tips = sc["tips_gross"] * (1 - PLAY_CUT)  # coffee IAPs take Play's cut
        total = android_net + ios_net + tips

        print(f"\n=== {name.upper()} — production + Pro open "
              f"{sc['prod_from']} ===")
        print(f"{'month':7s}{'installs':>10s}{'cum':>7s}{'Pro sales':>10s}")
        for m, inst, c, s in rows:
            if inst or m >= sc["prod_from"]:
                print(f"{m:7s}{inst:10d}{c:7d}{s:10d}")
        print(f"pre-production months = internal beta only (no public "
              f"listing, no sales — runbook rule)")
        print(f"Android Pro: {sales_n} sales -> ${android_net:,.0f} net")
        print(f"iOS:         {ios_note} -> ${ios_net:,.0f} net")
        print(f"Coffee tips: ${tips:,.0f} net (${sc['tips_gross']} gross)")
        print(f"YEAR NET: ${total:,.0f}   | cumulative installs {cum:,}")

    print("\n=== health-gate cross-check "
          "(pricing.md: >= 0.5 % conv at >= 8k installs) ===")
    for name, sc in SCENARIOS.items():
        cum = sum(sc["curve"].values())
        if sc["spike"]:
            cum += sc["spike"][1]
            post = [v for m, v in sc["curve"].items()
                    if MONTHS.index(m) > MONTHS.index(sc["spike"][0])]
            cum += int(sum(post) * sc["halo"])
        print(f"{name:6s}: {cum:,} installs — "
              + ("gate observable" if cum >= 8000 else
                 "below the 8k observability gate"))

    print("\n=== price sensitivity (base-case volume, elasticity "
          f"{ELASTICITY}, net $/sale x sales) ===")
    base_sales = sum(round(v * SCENARIOS["base"]["pro_rate"])
                     for v in SCENARIOS["base"]["curve"].values())
    for p in (5.99, 7.99, 9.99, 12.99):
        conv_mult = (p / PRICE) ** ELASTICITY
        rev = base_sales * conv_mult * p * (1 - PLAY_CUT) * (1 - REFUNDS)
        print(f"  ${p:5.2f}: conv x{conv_mult:4.2f} -> base-case Pro "
              f"${rev:,.0f} net")
    print("  (lower prices never lose here — but $9.99 is the owner ruling;"
          "\n   Play Console price tests remain free to run once volume "
          "supports significance.)")


if __name__ == "__main__":
    project()
