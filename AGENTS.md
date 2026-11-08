# AGENTS.md — the agent contract for this repo

Rule zero of every development cycle in this repository — before writing
code, planning a mechanism, or asserting anything about the environment:

> **Consult the shared agent playbook first.**
> `Steiner-Bot/agent-playbook` @ `http://192.168.1.98/Steiner-Bot/agent-playbook.git`
> (working clone: `/workspace/Workspace/agent-playbook`)

This is an owner decision (2026-11-07, decision 15 in
[docs/project-plan.md](docs/project-plan.md)) and it exists because of
documented near-misses: mechanisms reinvented two pages away from their
answer, platform policy assumed instead of re-checked, environment facts
assumed instead of measured. The playbook is cheap; those were not.

## The cycle, start to finish

1. **Pull the playbook** (`git -C /workspace/Workspace/agent-playbook pull`
   — or clone it if absent) and read the doc that matches the task:

   | About to… | Read |
   |---|---|
   | touch anything in the sandbox (paths, env, tooling) | `docs/environment.md` |
   | run an issue chain, milestone, verdict, or kit delivery | `docs/process.md` |
   | fight a harness/tool quirk (adb, artifacts, sandbox, git) | `docs/agent-tooling.md` |
   | change CI, pipelines, signing, or delivery jobs | `docs/ci-cd.md` |
   | call the GitLab API | `docs/gitlab-api.md` |
   | send/receive mail (tester intake, kits by mail) | `docs/mail-pipeline.md` |
   | touch DNS/stalwart/brand domains | `docs/stalwart-api.md`, `docs/web-search.md` |
   | resume budget-project state (devices, issues, HEADs) | `docs/localbudget-state.md` |

2. **Work the repo's own doctrine** — the house promise in
   [README.md](README.md), the locked decisions in
   [docs/project-plan.md](docs/project-plan.md), and per-area docs under
   `docs/`. CI is the sole ship gate; no verdict on boards or issue closes
   without the owner's explicit word.

3. **Write lessons back before the session ends.** Transferable across
   projects → playbook (in the same commit flow that learned it). Project
   facts → this repo's `docs/`. If the playbook contradicts reality you
   just measured, reality wins — amend the playbook in the same shift and
   say so in the thread.

Precedence when sources disagree: **measured platform reality > playbook >
repo docs > session memory.**
