#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/scripts/lib/build-env.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$MODULE"
bash -n "$ROOT/scripts/build-env-audit.sh"

# Test the safe negative path without executing a compiler, package manager,
# or modifying the machine. All required commands must be reported as missing.
set +e
env PATH=/nonexistent /usr/bin/bash -c \
    '. "$1"; mu_check_build_environment' _ "$MODULE" \
    >"$TMP/negative.log" 2>&1
RC=$?
set -e

test "$RC" -eq 1
grep -Fq 'MISSING  command       gcc' "$TMP/negative.log"
grep -Fq 'MISSING  command       pkg-config' "$TMP/negative.log"
grep -Fq 'BUILD_ENV_STATUS=missing' "$TMP/negative.log"
grep -Fq 'BUILD_ENV_MISSING_COUNT=' "$TMP/negative.log"

echo 'V020_BUILD_ENV_NEGATIVE_TEST_PASS=True'
