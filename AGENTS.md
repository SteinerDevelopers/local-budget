# AGENTS.md — the agent contract for this repo

Five laws bind every agent session in this repository. They are the house
process (agent playbook) pinned to this repo; the playbook holds the full
law texts and their measured proofs — this file is the oath, not the library.

## Law 1 — Rule zero: the playbook speaks first

Before writing code, planning a mechanism, or asserting anything about the
environment: pull `Steiner-Bot/agent-playbook`
(`http://192.168.1.98/Steiner-Bot/agent-playbook.git`, working clone
`/workspace/Workspace/agent-playbook`) and read the doc matching the task
(task→doc map at the bottom). Transferable lessons get written back to the
playbook in the same shift; project facts land in this repo's `docs/`.
Precedence when sources disagree: **measured platform reality > playbook >
repo docs > session memory.** (owner decision 15, 2026-11-07)

## Law 2 — The review lane: every diff gets a second reader

Before any commit pushes, its diff goes through the advisory ollamatest
lane (`ollamatest` skill; owner ruling 2026-11-08): one packet per commit —
one-sentence intent + the diff + the law it serves — asking only what the
lane is scored for (correctness, broken contracts, missed test surfaces,
edge cases). It is never asked about secrets, architecture, or user-facing
copy (proven blind there). Every finding is adjudicated against the real
code: adopt, or dismiss with a one-line reason in the commit body. Commits
carry the trailer `ollamatest: reviewed`, or `ollamatest: skipped
(unreachable)` when the server is down. A BLOCK touching crypto constants,
manifests, or the privacy laws does not rework-and-ship — it stops and
comes to the owner. Full law: playbook `docs/review-lane.md`.

## Law 3 — CI is the sole verdict

Local gates before push (playbook `docs/ci-cd.md` gate table); CI passes or
it didn't happen. No board verdicts and no issue closes without the
owner's explicit word. Report-only gates stay report-only unless the owner
escalates them (report-only law). A number quoted in a doc is emitted by a
committed instrument, or carries the command that regenerates it; an empty API
field means *undisclosed*, never *absent* (playbook `docs/measurement.md`).

**`main` is MR-only** (owner ruling, 2026-11-09; playbook `docs/process.md`): there
is no direct push to `main`. Work lands as a merge request whose pipeline is green
and whose review threads are resolved, the lane trailer goes in the MR description,
and **an agent never merges its own MR**. GitLab CE cannot enforce that last part —
approvals are recorded on CE but cannot be required (`merge_requests/:iid/approvals`
→ 200; `approval_rules` and the project-level `/approvals` → 404), an agent may approve
its own MR, and the bot holds **Owner (50)** merge rights — so it is law rather than
platform, and the weekly self-merge count is the evidence it held. A refused push is
the gate working: report it, and never un-protect a branch to keep moving.
Mechanics, the outage coupling, and the owner-only break-glass:
`docs/release/merge-gate.md`.

## Law 4 — The owner-gate ledger

Agents never self-approve: crypto constants and iteration policy;
signing/keystore custody (the decision 13 ceremony); store-track presence
(anything on Play's rails); pricing; any user-facing promise sentence;
escalating a report-only gate to blocking. Present measured options — the
owner rules — the issue note records it. Everything else the agent takes
without asking and announces in the thread.

## Law 5 — Device laws (this project ships to phones)

Walks re-dump the hierarchy before every tap; screenshots adjudicate; kit
identity is its pipeline sha (fresh GET → `pipeline.sha` →
`merge-base --is-ancestor` before believing any walk result); teardown uses
`--no-uninstall`; user-facing compute longer than a heartbeat runs detached
with an honest `m:ss` clock, and cancel promises only what the machine can
keep (shipping-ceremony law). Full texts: playbook
`docs/device-walk-laws.md`, `docs/process.md`.

---

## The playbook doc map (Law 1)

| About to… | Read |
|---|---|
| sandbox paths, env, toolchain facts | `docs/environment.md` |
| run an issue chain, milestone, verdict, kit delivery | `docs/process.md` |
| stage a decision for the owner or rule on one (rollup, default-on-silence, queues) | `docs/decision-economy.md` |
| produce or refresh an outward-facing artifact (deck, submission, kit, store copy) | `docs/version-discipline.md` |
| harness/tool quirks (adb, artifacts, sandbox, git) | `docs/agent-tooling.md` |
| change CI, pipelines, signing, delivery jobs | `docs/ci-cd.md`, `docs/adoption.md` |
| run the review lane | `docs/review-lane.md` |
| walk a device | `docs/device-walk-laws.md`, `docs/flutter-test-laws.md` |
| design or change any UI, user-facing copy, or permission ask | `docs/ux-ruleset.md` (decision 17: binding — audit mode gates releases, build mode binds design) |
| call the GitLab API | `docs/gitlab-api.md` |
| assert a number, grade a process, or measure anything | `docs/measurement.md` |
| tester mail, kits by mail | `docs/mail-pipeline.md` |
| DNS/stalwart/brand domains | `docs/stalwart-api.md`, `docs/web-search.md` |
| resume budget state (devices, issues, HEADs) | `docs/localbudget-state.md` |
