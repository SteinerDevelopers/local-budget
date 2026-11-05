#!/usr/bin/env bash
# Local mirror of the CI gates (.gitlab-ci.yml), to run BEFORE pushing —
# the class of failure it prevents: green locally, red on CI because CI
# also gates dart format and commit subjects.
#   usage: tool/ci_local.sh                 # all dart packages + commit lint
#   usage: tool/ci_local.sh core capture    # only the touched packages
#   tool/ci_local.sh app                    # adds flutter analyze+test (slow)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== commit-lint (HEAD) =="
SUBJ=$(git log -1 --pretty=%s)
echo "$SUBJ" | grep -Eq '^(feat|fix|test|docs|refactor|chore|ci|perf|style|build|revert)(\([a-z0-9-]+\))?!?: .{3,}' \
  || { echo "NOT conventional-commits: $SUBJ"; exit 1; }
echo "OK: $SUBJ"

PKGS=("$@")
[ ${#PKGS[@]} -eq 0 ] && PKGS=(core data capture budget billing)

for p in "${PKGS[@]}"; do
  case "$p" in
    app)
      echo "== app: flutter analyze + test =="
      ( cd app && flutter analyze && flutter test --reporter compact )
      ;;
    *)
      echo "== $p: analyze + format + test =="
      ( cd "packages/$p" \
        && dart analyze --fatal-infos \
        && dart format --output=none --set-exit-if-changed . \
        && dart test --reporter compact )
      ;;
  esac
done
echo "ALL LOCAL CI GATES PASS"
