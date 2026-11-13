# Perf series A2 → B → C — close-out data and lessons (2026-11-13)

Bench protocol: identical-content samples, `soak_loop` 3 h windows, gap 1800 s,
SHEET = 8 typed QuickAdd saves (p99 of build+raster, profile kits). Closure
band pre-registered with the owner before C ran: C median within ±5 ms of
B's 92 ⇒ no net gain ⇒ close with data. Gate to ship remains verge <~50 ms
AND tablet regression <2 pts.

## Data (SHEET p99 medians, verge Tab-A9-line / tablet Tab A9+)

| kit | tree | verge raws (ms) | verge med | tablet med | safety |
|---|---|---|---|---|---|
| A2 baseline | main@91ea203a (n=10) | 80–126 | **108** | 30 | clean |
| B | A2 + watchMonth hoist (n=6) | 66–99, bimodal | **92** | 31 | 12/12 zero |
| C | B + day-totals hoist (n=6) | 81,95,88,92,104,116 | **93.5** | 33 | 6/6 zero |

C median 93.5 vs B 92: Δ1.5 ms, inside the ±5 band ⇒ **C = no net gain,
closed with data** (!39). Tablet C 33 vs B 31: Δ2, at the borderline; with
n=6 and no mechanism for a hoist to slow raster, recorded as noise-floor,
flagged for the fleet replication (D-Tier 4).

## Lessons (pre-registered + earned)

1. **The tail is not the hot spots we removed.** Both hoists moved the LOW
   mode's floor (B 66–99 bimodality first characterized here); the HIGH mode
   survived both series intact. Verge high-mode cost is therefore structural —
   candidate axes are storage (WAL/checkpoint), GC, and scheduler/DVFS — not
   call-path waste. This is exactly what the D-tier instruments (#60) now
   measure; attribution precedes further micro-optimization.
2. **Pre-registered closure bands keep verdicts honest.** The ±5 contract was
   agreed before the first C pair; writing the close-out at Δ1.5 required zero
   goalpost negotiation. Process precedent: copy it into the playbook digest.
3. **n=6 cannot resolve 1.5 ms.** Correct response is not more pairs of the
   same; it is a better instrument (per-save slices, feature vectors).
4. **A real delta that misses the gate stays honest too.** B's 108→92 was
   measured on identical content and is credible, but <50 is the gate and
   "no ships on faith" is the law: !40 holds until attribution knows whether
   the residual is structural, at which point B may re-emerge as part of a
   *explained* fix — not as a lone 16 ms hope.
5. **Null results from good instruments are knowledge** (owner, 2026-11-13).
   This document is the artifact proving the null is informative, not idle.

## Disposition recommended to owner
- !39 (C): close with this doc linked (band hit; nothing to merge).
- !40 (B): HOLD post-launch pending Tier-2 attribution.
- Launch Sunday proceeds on main regardless: neither branch was launch-critical.
