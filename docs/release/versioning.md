# Version & build-number discipline

_E9 groundwork, 2026-11-05. One rule above all: **a versionCode that
shipped once must never ship again**, in any flavor, track, or channel.
Play enforces this monotonically per package; sideload testers hit it as
"downgrade failed" long before the store does._

## Current state (verified 2026-11-05)

- `app/pubspec.yaml` carries the **only** version source: `version:
  0.1.0+1` → `versionName 0.1.0`, base `versionCode 1`.
- `app/android/app/build.gradle.kts` maps `flutter.versionCode` /
  `flutter.versionName` into both flavors and does **not** override them
  (per-ABI splits get Flutter's automatic +1000/+1000000 offsets — only
  `arm64-v8a` ships today, so the shipped code equals the base number).
- Debug kits built by `package-apk-free` / `package-apk-pro` therefore
  all carry versionCode 1 — fine while nothing is on Play, **not fine
  the moment any track or beta APK exists**, because a kit would then
  install OVER or fight with real builds. Testers key kits off the
  7-char commit in the filename (FIND-ME.txt convention), not the
  version, so we can decouple safely now.

## Rules

1. **`version:` in `app/pubspec.yaml` is the single source of truth.**
   No hard-coded `versionCode` in gradle files, no `--build-name` flags
   in jobs. Bump it in a release-prep commit tagged in the changelog.
2. **Beta/production builds inject the build number from CI** and never
   rely on the checked-in `+1` surviving:
   `--build-number=$VERSION_CODE` (flutter owns versionCode via
   `flutter.versionCode`; raw `-P` injection would be ignored), with
   `VERSION_CODE` recorded in the
   job log + release notes. Candidate sources, in order of preference:
   manual pipeline variable at release time (explicit), else a
   monotonic mapping like `1000 + CI_PIPELINE_IID` (unique per project
   pipeline; grows forever — acceptable while base stays 1-ish), else
   fail the job rather than reuse.
3. **Debug sideload kits (E11 testing) keep the checked-in number** and
   are always labelled `localbudget-<flavor>-debug-<sha>.apk`; kits are
   never uploaded to any Play track.
4. **E9 release prep bumps `0.1.0+1` → `1.0.0+<N>`** in a dedicated
   `chore(release): bump version to 1.0.0+N` commit; the tag
   `v1.0.0+N` is cut from that commit and the Play release notes quote
   it. After the first Play upload, rule 2 stops being optional: the
   first uploaded versionCode becomes the floor.
5. **free and pro are separate packages** (`.pro` suffix) with
   independent Play listings; they may share a versionCode number space
   (they're different apps to Play), but keep them equal anyway — one
   changelog, one release train.

## Worked example (the future `package-apk-release` job)

```yaml
package-apk-release:
  extends: .apk-base
  when: manual
  variables:
    VERSION_CODE: "1001"   # set explicitly per release; bump or fail
  script:
    - ...
    - >
      flutter build apk --release --flavor free
      --dart-define=APP_FLAVOR=free
      --build-number="$VERSION_CODE"
      --split-debug-info=build/symbols
```

The job must refuse to run if `VERSION_CODE` is unset or already
recorded in `docs/release/shipped-versions.md` (create that ledger on
first use: one line per upload — flavor, versionName, versionCode,
track, pipeline URL).

## Audit checklist for the release job PR

- [ ] gradle files still free of literal `versionCode`
- [ ] job fails closed when `VERSION_CODE` missing/duplicate
- [ ] `shipped-versions.md` updated in the same release
- [ ] FIND-ME.txt / registry path convention unchanged for debug kits
      (testers keep the debug lane until production is live)
