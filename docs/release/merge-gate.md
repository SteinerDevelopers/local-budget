# Merge gate on `main` — what it enforces, and the break-glass

Applied **2026-11-09** by owner ruling, after the process grade found
**0 merge requests fleet-wide across 659 commits on default branches in 30 days**
(301 of them on this repo) — measured before the gate by
`deliverables/tools/mr-audit.mjs`, and re-runnable in one command.

The repo had a "protected" `main` the whole time. Protection was not the gap:
`push_access_levels` was **Maintainer**, a role every actor here holds, so the
protected branch sat on an open door. Enforcement is one field, and it is now
`No one`.

## What the platform enforces

| Setting | Value | What it stops |
|---|---|---|
| `main` `push_access_levels` | **No one (0)** | Any direct push to `main`, by anyone — including the owner and this agent |
| `main` `merge_access_levels` | Maintainer (40) | Who may land an MR |
| `only_allow_merge_if_pipeline_succeeds` | `true` | Merging a red or unfinished pipeline |
| `only_allow_merge_if_all_discussions_are_resolved` | `true` | Merging while a review thread is open |

Read them back (controls are GETs, never the write's own response):

```sh
curl -sS -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  http://192.168.1.98/api/v4/projects/10/protected_branches
curl -sS -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  http://192.168.1.98/api/v4/projects/10 | grep -E 'only_allow_merge'
```

## What it means day to day

- Branch, commit, push the branch, open an MR against `main`. The lane trailer
  (`ollamatest: reviewed`) goes in the **MR description**; the MR is the unit of
  review now, not the commit.
- **An agent never merges its own MR.** GitLab CE cannot enforce this
  (`/approvals` → **404**; approval fields absent from the project projection), and
  the bot is a Maintainer with merge rights — so *being able to merge is not
  permission to merge*. The weekly self-merge count from
  `deliverables/tools/mr-audit.mjs` is the only *machine-checkable* evidence that the rule held.
- The release path is unchanged: `kit/*` and `v*` tags stay protected at
  Maintainer, kit jobs run on branch and MR pipelines, and `cut-release` still
  requires a green kit job plus a published package before it writes a tag.
- A refused push is the gate working. Report it; do not "fix" it.

## Break-glass — owner only

**For:** the merge path is coupled to artifact upload. On 2026-11-09 three jobs
across two projects finished their script successfully and then died in the upload
(`500 Internal Server Error` ×3 → `FATAL: upload failed with no response from
coordinator`) inside a ~5-minute window, on both 118 MB and few-hundred-byte
artifacts. During that class of outage **nothing merges, hotfix included**.

Revert the merge gate — **both** flags, or merges stay blocked and the break-glass
has become a mystery:

```sh
curl -sS -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "only_allow_merge_if_pipeline_succeeds=false" \
  --data "only_allow_merge_if_all_discussions_are_resolved=false" \
  http://192.168.1.98/api/v4/projects/10
```

An unresolved review thread blocks a merge on its own, so a one-flag revert reverts
half the gate. Both flags go off together and both come back the same day.

Then: record it as a note on the issue or MR it unblocked, say so in the thread, and
set it back to `true` the same day. This file is the only copy of the command, so
this file is what makes the difference between a documented override and an
untraceable one.

**Two things that are NOT the break-glass:**

- **Setting `main` back to `push_access_levels=40`.** That does not unblock a hotfix
  any faster than the flag does; it removes the gate *silently and permanently*, and
  a 5-minute infrastructure fault becomes the new architecture. If anyone has done
  it, that is an incident to report, not a workaround.
- **Deleting or recreating the protected branch rule** to "reset" it.

## Full undo (also owner-only)

**This instance has no update route for protected-branch rules.** Measured
2026-11-09: `PUT /projects/10/protected_branches/9` and `PUT …/main` both answer
**404** in form and JSON shapes, and even `GET /protected_branches/9` is 404 — only
the collection `GET` and `POST` work, plus `DELETE`, which keys on the **branch
name**, not the rule id. So the rule is changed by replacing it:

**Capture the current rule before you touch it** — this is what makes the window
recoverable, and it is the reason the sequence below is one block instead of three
copy-pasted commands:

```sh
B=http://192.168.1.98/api/v4/projects/10; TOK=$GITLAB_TOKEN

# 0. capture the rule you are about to replace — this is the recovery path
curl -sS -H "PRIVATE-TOKEN: $TOK" $B/protected_branches > /tmp/main-rule.json
grep -o '"name":"main"' /tmp/main-rule.json >/dev/null || { echo "no main rule captured — STOP"; exit 1; }
WAS=$(python3 -c 'import json
r=[x for x in json.load(open("/tmp/main-rule.json")) if x["name"]=="main"]
print(r[0]["push_access_levels"][0]["access_level"] if r else "")' 2>/dev/null)
[ -n "$WAS" ] || { echo "cannot read the captured level — open /tmp/main-rule.json, set WAS by hand, then continue"; exit 1; }

# 1. delete, then 2. create, capturing both status codes instead of watching them scroll
DEL=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H "PRIVATE-TOKEN: $TOK" $B/protected_branches/main)
CRE=$(curl -sS -o /tmp/cre.json -w '%{http_code}' -X POST -H "PRIVATE-TOKEN: $TOK" \
  --data "name=main" --data "push_access_level=40" --data "merge_access_level=40" \
  --data "allow_force_push=false" $B/protected_branches)
echo "delete=$DEL create=$CRE"

# 3. the compensation runs ONLY when the create failed, and restores what you captured
if [ "$CRE" != "201" ]; then
  echo "CREATE FAILED — main is UNPROTECTED, restoring push_access_level=$WAS"
  curl -sS -w '\nrestore=%{http_code}\n' -X POST -H "PRIVATE-TOKEN: $TOK" \
    --data "name=main" --data "push_access_level=$WAS" --data "merge_access_level=40" \
    --data "allow_force_push=false" $B/protected_branches
fi

# 4. read it back; ?name= does NOT filter, so read the whole list and grep locally
curl -sS -H "PRIVATE-TOKEN: $TOK" $B/protected_branches
```

`WAS` is parsed, not grepped: a `grep '"name":"main".*"access_level':*` matches
greedily to the **merge** level on the same line, and a recovery path that restores
the wrong field is worse than no recovery path. Parse JSON as JSON, or read the file
and set the value by hand.

The compensation is conditional on purpose. A restore that always runs is not a
compensation — after a successful create it would just return `409 already exists`,
and after a *failed delete* it would look like a restore while changing nothing. The
level it puts back is read out of the file captured at step 0, not out of memory.

**Two traps in that sequence, both measured here:**

- Use **`push_access_level` / `merge_access_level`** (singular). The array syntax
  `push_access_levels[0][access_level]=0` — and the JSON equivalent
  `{"push_access_levels":[{"access_level":0}]}` — is **accepted with 201 and silently
  ignored**: the rule comes back `Maintainers`. A call that reports success and does
  the opposite of what you asked for is the worst kind of failure, and it is exactly
  what a reader would copy from GitLab's docs.
- **Steps 1 and 2 are a window in which `main` is unprotected.** Run them
  back-to-back, read back immediately, and if step 2 fails, recreate the previous
  rule at once. Never leave this file with the delete already run and the create
  "for later".

The two project-level flags revert normally — `PUT /projects/10` with form fields
answered **200** here:

```sh
curl -sS -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "only_allow_merge_if_pipeline_succeeds=false&only_allow_merge_if_all_discussions_are_resolved=false" \
  http://192.168.1.98/api/v4/projects/10
```

After 2026-11-09 every change to this document reaches `main` through the gate it
describes. That is deliberate: the rule is reviewed the way it is enforced.

## State as applied

Read back from the GET above on **2026-11-09**, the day the gate went on:

| Setting | Live value |
|---|---|
| `main` direct push | **No one** |
| `main` merge | Maintainers |
| `main` force push | `false` |
| pipeline must succeed | `true` |
| discussions must resolve | `true` |

**What each of those rows is actually proved by** — because a read-back and a
refusal are different kinds of evidence, and the runbook should not blur them:

- The table itself is what GitLab *reports*, read from the API.
- The push row is also what GitLab *does*: `git push origin main` ends in
  `! [remote rejected] main -> main (pre-receive hook declined)` and writes nothing
  server-side. A setting nobody tried to violate is a belief, not a gate.
- The two merge-side flags are **not** exercised by that probe. They will be proved
  the first time a merge request is refused for a red pipeline or an open thread —
  until then this doc states them as configured, not as observed.

The probe commit was discarded and `main` was left exactly where it was. This
document reached `main` the way everything else now must: as a merge request.
