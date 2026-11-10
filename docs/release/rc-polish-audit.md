# §4.5 RC polish audit — status vs the binding acceptance bar

_E9 groundwork, 2026-11-05. §4.5 (feasibility, decision 10) is binding:
findings here that block retention are launch-blocking. Status legend:
✅ done + guarded, 🟡 implemented but needs device/RC verification,
⬜ open work. The RC usability gate (5 testers) is the verdict mechanism;
this page only says where the code stands before that gate._

## Measurable acceptance targets

| Target | Status | Evidence / gap |
|---|---|---|
| First logged transaction < 3 min; onboarding optional, no forced tour | ✅ | No tour exists; Home lands directly, QuickAdd opens on one tap. Nothing blocks the first entry. |
| Manual expense ≤ 3 interactions (amount → chip → save), median < 15 s | ✅ | QuickAdd sheet is exactly that flow; guarded by `quick_add_sheet_test.dart` (pad → chip → save) and `data_flows_test.dart` end-to-end. |
| Scan → review → save < 30 s median; uncertain fields highlighted; every field editable in place | 🟡 | Flow exists (E2/E11) incl. the new bill/statement routing; review sheet edits in place. **Measured 2026-11-10 on the bench pair** (`measurements/2026-11-10/`): OCR path 15.0 s (Flip6) / 25.7 s (VERGE) — under the bar; manual-entry path (what the free flavor hits on total-less receipts without Gemini Nano) 32.7 s / 45.4 s — over it. The 5-tester RC gate stays the verdict; the bench numbers say the *manual* fallback needs the stopwatch too. |
| 60 fps mid-range; camera launch < 1 s; skeletons not spinners; no UI-thread blocking | 🟡 | OCR/parse run in the pipeline worker (isolate) — architecture holds. **Measured 2026-11-10** (`measurements/2026-11-10/`): cold start Flip6 1304 ms / VERGE ~4.5 s wall-clock; scripted gfxinfo: VERGE 3.4% and Flip6 21.4% janky — both above the <1% bar (small N, wireless-inflated, README Finding 5; the flagship number is the open ⚠); camera launch measures 5–8 s but the floor is the ML Kit doc-scan activity, not our UI (Finding 4). "60 fps audit" checkbox on #10: partially checked, jank re-run owed. |
| Nothing ever lost: auto-saved drafts, undo on destructive actions, never-auto-commit scans | ✅ | Scan results are always reviewed before commit; ledger delete has undo snackbar (E1, tested); bill materialization is idempotent. **Gap: draft persistence for a half-typed QuickAdd across process death is not implemented** — decide at RC whether §4.5's "auto-saved drafts" extends that far or is satisfied by the short flow. |
| One-hand/thumb-first; dark-mode parity; WCAG AA; font scale ~2×; TalkBack passes; haptics on save/correction/error | 🟡 | Bottom bar + sheets are thumb-first; goldens cover light+dark; palette AA-checked (E1 a11y pass); overflow suite covers 1.0×/1.3× at 320 dp incl. the new add bars. **Measured 2026-11-10** (`measurements/2026-11-10/`): TalkBack semantic pass both devices (0 clickable-unlabeled across Home/Bills/Budgets/Goals/QuickAdd/scan chooser); 2× font sweep ran — **QuickAdd clips at 2.0 on both phones** (`$0` amount overflows right edge, 3rd category chip clips): remaining work item 2 below, now with evidence. |
| Empty states teach, errors coach, Help reachable from every screen | ✅ | Empty states carry the primary action ("No bills yet" + Add); help articles per epic + `HELP_ENTRY_POINTS` completeness test (#39) guards reachability. |

## Process commitments

- **Usability gates at MVP and RC (5 testers each)** — MVP round done
  during E1–E3 dogfood; **RC round not scheduled** — needs the release
  build first (fastlane + signing exist only as scaffolding:
  `docs/release/versioning.md`, `fastlane/`).
- **No telemetry**: all remaining rows above must be measured by hand
  during the RC gate; that is the price of the zero-data stance.

## Concrete remaining RC-polish work (ordered)

1. Device measurement day — **ran 2026-11-10 on the bench pair (Flip6 +
   VERGE; owner ruling: VERGE is the mid-range reference)**; numbers,
   instruments and honest caveats in `measurements/2026-11-10/`.
   Owed repeats: longer-window gfxinfo on Flip6 (Finding 5), camera
   re-measure past the ML Kit first-run dialog (Finding 4).
2. 2× font-scale sweep — QuickAdd clipping **measured on both bench
   phones 2026-11-10** (README Finding 2); extend the overflow suite to
   `textScaleFactor: 2.0` on Home + review sheet (expect real findings;
   budget a follow-up layout fix commit, do not pad-scope it here).
3. Decide the QuickAdd draft question (above) before the gate, not
   during it.
4. Data Safety form entry from `docs/store/data-safety.md` (mechanical
   once the Play Console account is live — owner's).
5. Sign up beta track + fastlane `internal` lane run once (proves the
   pipeline end-to-end before production pressure).

None of 1–3 needs new permissions or architecture; all are inside the
E9 epic as written.
