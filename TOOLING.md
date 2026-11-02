# Tooling & environment notes

## AI dev sandbox (where most code is written today)

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
- No `python3` in this image; use `tr`/`grep`/`sed` for JSON poking.

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

## Flutter app scaffold (once `app/` exists)

`flutter create --org dev.steiner --project-name local_budget --platforms android,ios app`
Android build needs JDK 17 (`JAVA_HOME` above). No Android SDK in this sandbox yet —
APK builds run in CI or after `sdkmanager` install; `flutter test` (unit/widget)
needs neither.
