# Tooling & environment notes

## AI dev sandbox (where most code is written today)

**Rule zero before anything below** (decision 15): every development cycle
starts by pulling and consulting the shared agent playbook — see
[AGENTS.md](AGENTS.md) at the repo root. It already knows most of what this
file knows, plus the platform scars this file doesn't.

Linux x86_64 container, no `/dev/kvm`, `/home/node` is read-only. Every shell is
fresh, so **source the env file first** in every command:

```bash
source /workspace/Workspace/tools/env.sh
# exports: FLUTTER + Dart SDK on PATH, JAVA_HOME (JDK 17),
#          PUB_CACHE=/workspace/Workspace/tools/pub-cache,
#          HOME=/workspace/Workspace/tools/home   (both redirects are mandatory:
#          flutter refuses to bootstrap when ~/.pub-cache or ~/.config are unwritable)
```

Toolchain: Flutter 3.47.9 stable / Dart 3.13.7 at `/workspace/Workspace/tools/flutter`.
Quality gate per package: `dart format . && dart analyze --fatal-infos && dart test`.

Sandbox gotchas learned:

- `RegExp()` is not a `const` factory — `static final List<RegExp>` only.
- Raw strings do **not** interpolate `$_identifier` in Dart 3.13 — verified; inline
  regex fragments instead of composing with `$var` inside `r'...'`.
- The new formatter re-wraps long single-line `if (x) return;` bodies and can drop
  intent — always run `dart analyze` *after* `dart format`.
- No `python3` in this image; **jq 1.7 is available** (`/usr/bin/jq`) — parse all
  `glab api` JSON with it, never `tr`/`grep`.

## Drift / data package

Codegen: `dart run build_runner build --delete-conflicting-outputs` (generated
`database.g.dart` is committed — CI does not re-run codegen).
SQLite: runtimes ship `libsqlite3.so.0` but Dart's default loader wants the
`libsqlite3.so` symlink from the `-dev` package — tests override the loader
(`sqlite3/open.dart`), CI installs plain `libsqlite3-0`.

## GitLab CI (`SteinerRunner`)

One shared instance runner, tag `SteinerRunner`, Docker executor on a QEMU VM:
8 vCPU, 15 GiB RAM, ~62 GB disk, registry egress OK, **no `/dev/kvm` inside job
containers** (verified by probe pipeline #8, 2026-11-02 — re-run `runner-probe`
manually after any runner change). Emulator tiers need a `devices = ["/dev/kvm"]`
passthrough in `config.toml` first (feasibility §6.1).

CI hygiene: lint before pushing —
`glab api projects/10/ci/lint -X POST -f content="$(cat .gitlab-ci.yml)"`.
Multi-line job scripts must use block scalars (`- |`): an unquoted YAML scalar
containing `": "` silently corrupts job parsing.

CI images that work here: `dart:stable` and `alpine` (Docker Hub) +
`ghcr.io/cirruslabs/flutter:stable` (**pinned at Flutter 3.44 / Dart 3.12 —
cirrus never published newer; the app SDK floor `>=3.12` is validated by it**).
`cirruslabs/flutter` on Docker Hub no longer exists. The flutter image is ~2.7 GB
and `pull_policy = always` re-pulls every job (~11 min on this VM) — ask the
runner admin for `pull_policy = "if-not-present"` before E2 doubles job count.

## Flutter app scaffold (once `app/` exists)

`flutter create --org dev.steiner --project-name local_budget --platforms android,ios app`
Android build needs JDK 17 (`JAVA_HOME` above). No Android SDK in this sandbox yet —
APK builds run in CI or after `sdkmanager` install; `flutter test` (unit/widget)
needs neither.

## OCR benchmark corpus & harness (#31)

Device × screenshot matrix for the capture pipeline (`packages/capture/tool/`).
Deterministic: a fixed 5×7 bitmap font (latin + upper-case Cyrillic), a seeded
RNG, and a hand-rolled PNG writer — byte-stable corpus with no fonts or image
packages involved.

```bash
cd packages/capture
dart run tool/corpus_gen.dart --out corpus [--seed N] [--per-cell K]   # 2 scripts x 3 res x 2 modes
dart run tool/benchmark.dart --corpus corpus --backend gold \
    [--budget 0.85] [--reps 5] [--log tool/results.jsonl]
```

- `corpus/` is gitignored; regenerate any time. Each image ships a manifest
  entry (ground truth + gold lines) and a `<image>.lines.txt` sidecar.
- **`--backend gold`** replays the manifest's ground-truth lines as the
  `TextExtractor` — measures Tier-2 heuristics and the timing floor. Runs
  anywhere pure Dart runs (sandbox, runner, mini-PC), no device.
- **`--backend sidecar`** reads `<image>.lines.txt` next to (or under
  `--sidecars DIR`) each image. On device: `adb push corpus/ /data/local/tmp/`,
  run the app's ML Kit `TextExtractor` adapter over each PNG dumping its lines
  into the sidecar, `adb pull`, then benchmark with `--backend sidecar`.
  Missing sidecars are counted, not fatal (partial device runs).
- Regression budget: grand-total **precision ≥ 0.85** across all images
  (exit code 2). Every run can be logged append-only as JSONL (`--log`):
  sha, backend, seed, per-cell P/R, p50/p95 latency.
- Reading the table: gold/latin should sit at 100/100. gold/cyrillic shows
  **merchant and total recall = 0 by design of Tier-2** (anchor words and the
  letter filter are Latin-only) — the harness exists to track that gap; the
  fix belongs in `core` heuristics (ИТОГО & co.), not in this tool.
- Not a sandbox CI gate (needs corpus-sized disk + no value without devices);
  on the KVM runner the sidecar backend is the device OCR gate.



## Kit builds (integration-test APK trios)

    source tools/env.sh                      # JAVA_HOME, flutter, adb PATH
    export ANDROID_HOME=<sdk> HOME=<tools/home>
    flutter build apk --profile --flavor free -t integration_test/<x>_test.dart

Hardening (stale-artifact incident 2026-11-12, #55 note): wipe
build/app/outputs/flutter-apk BEFORE and AFTER each build; copy with &&
so a failed build can never harvest leftovers; record md5+timestamp per
apk into KIT-IDENTITY.txt. Device perfetto is old-gen: trace configs
must use nested `data_sources { config { ... } }` TRACE_CONFIG format,
not the colon text format (probe.sh carries the working example).
