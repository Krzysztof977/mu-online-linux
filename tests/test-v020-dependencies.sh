#!/usr/bin/env bash
# Read-only smoke test of v0.2.0 dependency routing on CachyOS.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/v020-dependencies.sh"
bash -n "$SCRIPT"
echo 'V020_DEPENDENCY_DISPATCH_SYNTAX_PASS=True'

# This test must never start Wine, run a package transaction, or need sudo.
# Other distribution branches need independent VM tests.
. /etc/os-release
if [[ "${ID:-}" != cachyos ]]; then
    echo 'V020_DEPENDENCY_DISPATCH_CACHYOS_TEST_SKIPPED=True'
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
bash "$SCRIPT" --check >"$TMP/report" 2>&1
grep -Fxq 'V020_DEPENDENCY_ROUTE=cachyos-pacman' "$TMP/report"
grep -Fxq 'PACMAN_DEPENDENCIES_ALREADY_INSTALLED=True' "$TMP/report"
grep -Fxq 'V020_BUILD_ENV_PREFLIGHT_PASS=True' "$TMP/report"
grep -Fxq 'V020_PACMAN_DEPS_PREPARED=True' "$TMP/report"
echo 'V020_DEPENDENCY_DISPATCH_CACHYOS_PASS=True'
