# Changelog — Steiner Budget

The version source of truth is `app/pubspec.yaml` (`version: 0.1.0+1` →
`versionName 0.1.0`, `versionCode 1`). This file is the second of the three
bindings the playbook (`Steiner-Bot/agent-playbook`, `docs/version-discipline.md`)
law 1 requires — human marker, changelog, VCS tag — and it exists so that a kit
installed on a phone can be traced back to a commit without opening a job log.
Created 2026-11-09; before that date this repo carried no changelog at all, the
same gap the process grade recorded under its Release dimension.

`docs/release/versioning.md` rule 4 is still ahead of this file: the
`0.1.0+1 → 1.0.0+<N>` bump is a release-prep commit and `v1.0.0+N` is the tag
that comes with it. Nothing here pre-empts that; the `kit/*` namespace is for
build snapshots, `v*` for the app release.

## 0.1.0+1 (beta line)

### kit/v0.1.0-beta-2026-11-09 — `dc81d2b2`, 2026-11-09

First kit cut through the release channel. Pipeline `430` built both flavors and
its `kit-release` job published the pair to the generic package registry and read
every file back before this tag was written. Job numbers below (`4323`, `4370`,
`4329`) all live **inside pipeline 430**: GitLab job ids are fleet-wide and share
no numbering with pipeline ids, and a retry creates a new job instance within the
same pipeline rather than a new pipeline.

| kit | bytes | sha256 |
|---|---|---|
| `app-arm64-v8a-free-debug.apk` | 117,625,488 | `a858e770a83c8388e7ad4e26b2176aee517194e44c8021ce3e10ccd9fedefd31` |
| `app-arm64-v8a-pro-debug.apk` | 117,613,187 | `1c9d887d9398f896576c683b9704f78107f067ad75855442f9e470b157845ed6` |

Published at
`http://192.168.1.98/api/v4/projects/10/packages/generic/localbudget-kit/dc81d2b2/`
as both APKs plus `KIT-SHA256SUMS.txt` (189 B, the standard two-line
`sha256sum -c` format covering both flavors). A tester verifies with — the sums name the two APKs, so all three files must sit
in the same directory:

```sh
BASE=http://192.168.1.98/api/v4/projects/10/packages/generic/localbudget-kit/dc81d2b2
for f in KIT-SHA256SUMS.txt app-arm64-v8a-free-debug.apk app-arm64-v8a-pro-debug.apk; do
  curl -sS -o "$f" "$BASE/$f"
done
sha256sum -c KIT-SHA256SUMS.txt   # both lines must print OK
```

Every size and digest in this entry is re-emitted by one command, so the file
never becomes the last true copy of them (Law 3):

```sh
curl -sS -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  http://192.168.1.98/api/v4/projects/10/packages/generic/localbudget-kit/dc81d2b2/KIT-SHA256SUMS.txt
```

**Which job produced these bytes, stated exactly.** Job `4323`
(`package-apk-free`) built the free APK and finished 13:05Z. The pro APK came
from job **`4370`**, not from the job that first attempted it: `4324` compiled
pro successfully at 13:11Z and then lost the artifact upload to three `500`s
from the GitLab coordinator (`FATAL: upload failed with no response from
coordinator`), so its bytes never reached the server and its digest never
reached the publish step. `needs:` held `kit-release` in a non-playable state
across both attempts, and `4370`'s success at 13:34Z is what released the lock
on publishing. Recording the retried job id matters because a kit's provenance
is the identity of the job whose artifacts were hashed, and the first attempt's
artifacts do not exist.

Publishing was job `4329` (`kit-release`): it verified each APK against the
digest written by that flavor's own build, uploaded three files (`201` each),
and read all three back (`200` each) — the tag and Release were written only
after that.

These are **debug-signed `arm64-v8a` debug builds** made with the pinned debug
keystore for the `beta` venue. They are not store artifacts: no Play upload has
happened for this app, signing custody is owner-gated, and `x86_64`/`armeabi-v7a`
are not part of this kit.

The changelog entry lands **after** the tag rather than inside it, because a kit
is a snapshot of its build commit (version-discipline law 2); moving the tag to
include this file would misattribute the APKs.

### Before the channel

Ten kits were published by hand between 2026-11-05 and 2026-11-06 as
`localbudget-kit:<sha7>` and are still in the registry — 2,527 MiB of the
2,752 MiB the registry holds post-cut, both figures emitted by
`deliverables/tools/process-metrics-pass3.mjs` at stamps `13:27:45Z` and
`13:39:32Z`. They
carry no SHA-256 — four carry an MD5 that no build job wrote — so they cannot be
verified against any commit, and `cut-release` refuses to retro-tag them: there
is no green kit job at those commits to point at. Backfilling them would mean
rebuilding those bytes from their original commits, which is a decision, not a
cleanup.
