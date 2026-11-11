# Beta runbook (owner-fired steps; agents never run store rails)

Every step below is a **human action with a paste-ready command** — the
Law 4 boundary says store-track presence is owner-only. This doc exists
so the owner's beta work is execution, not composition. Nothing here
self-runs; agents prepare and verify after each owner step.

## 0. Prerequisites (one-time, ~30 min)

- [ ] Play Console service-account JSON at `fastlane/credentials/play.json`
      (git-ignored; grant it access on the app's Release page).
- [ ] Release keystore + `android/key.properties` (decision 13 ceremony —
      owner custody only; `release_bundle` currently TODOs signing).
- [ ] Version plan: pick `VERSION_CODE` per `versioning.md` rule 2
      (`1.0.0+<N>` release-prep commit + `v1.0.0+N` tag come with RC1).
- [ ] `docs/store/listing.md` `<owner>` blanks filled (pricing excluded —
      that's the pricing ruling, separate).

## 1. Internal-track build (first beta step)

```
cd fastlane && bundle exec fastlane internal VERSION_CODE=<N>
```

Expect: signed free-release AAB → INTERNAL track release named with the
version code; `supply` pushes metadata (images/screens stay manual until
the listing checklist is done — skips are intentional).

**Agent post-checks after each upload** (report, no action needed from
owner): flavor guard already CI-pinned; agent verifies via console export
or owner screenshot that the INTERNAL artifact is the CI `kit/*` sha or a
documented local build (kit identity pinned before any device claim).

## 2. Testers

- [ ] Internal list ≤ 100 emails (internal track needs no opt-in review).
- [ ] Direct testers to `beta@steinerdevelopers.dev` for feedback — the
      intake pipeline is live (lands in hello@ triage + lance@ copy;
      escalate-first policy: agent does not auto-reply to beta mail
      until reply templates are owner-approved).
- [ ] First-wave protocol: each tester reports device + install type
      (fresh vs upgrade-from-kit/*); upgrade reports get the schema
      matrix's faith — v1/v2→head paths are CI-pinned (migration_v1_v2).

## 3. Soak before widening

- [ ] 48–72 h bench soak result banked (needs the owner's soak-kit word —
      see playbook `docs/beta-readiness.md`).
- [ ] Crash posture decided (crash-telemetry stance vs local-first —
      decision brief available on request).

## 4. Closed beta (only if opt-in links are wanted)

Internal is sufficient for a named tester pool. Moving to `closed`
requires Google's testing criteria (12-tester·14-day counts for personal
accounts); decision stays owner-side, one fastlane line differs
(`track: "closed"`).

## 5. Rollout gates (RC → production, later, owner-worded)

Staged rollout 10 → 50 → 100 %, ≥ 24 h between steps; halt triggers:
any crash cluster > 0.5 % daily devices, any data-integrity report
(highest severity — the ledger is the product), or audit-mode UI findings
under the ux-ruleset gate.

## Rollback

Local-first means rollback is purely Play-side: stop rollout / roll back
to the previous internal release; no server state exists to unwind. Test
devices keep installed kits (teardown `--no-uninstall`), so reproducing
the rolled-back bug stays possible.

## Exit criteria for "beta is live"

- [ ] internal release published; smoke install + upgrade install green
- [ ] beta@ intake verified with one real external message (Gmail test in
      the runbook style: expect hello@ + lance@ copies)
- [ ] ≥ 1 tester on each: fresh install, upgrade from beta kit
- [ ] feedback loop closed at least once end-to-end (report → repro →
      fix MR → new kit)
