#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
check() {
    local name="$1" id="$2" like="$3" version="$4" expected_status="$5" expected_candidate="$6"
    printf 'ID=%q\nID_LIKE=%q\nVERSION_ID=%q\n' "$id" "$like" "$version" > "$TMP/os-release"
    bash "$ROOT/scripts/platform-audit.sh" "$TMP/os-release" > "$TMP/report"
    grep -Fx "DISTRIBUTION_STATUS=$expected_status" "$TMP/report" > /dev/null
    grep -Fx "PACKAGE_MANAGER_CANDIDATE=$expected_candidate" "$TMP/report" > /dev/null
    grep -Fx 'BUILD_ENV_STATUS=not_checked' "$TMP/report" > /dev/null
    grep -Fx 'V020_PLATFORM_DISCOVERY_PASS=True' "$TMP/report" > /dev/null
    printf 'PASS %s\n' "$name"
}
check fedora44 fedora '' 44 verified dnf
check fedora45 fedora '' 45 unverified dnf
check nobara44 nobara fedora 44 verified dnf
check ubuntu2604 ubuntu debian 26.04 verified apt
check cachyos cachyos arch rolling unverified pacman
check arch arch '' rolling unverified pacman
check derivative unknown 'arch linux' rolling unverified pacman
check unknown unknown '' 1 unverified none
bash -n "$ROOT/scripts/lib/platform-detect.sh"
bash -n "$ROOT/scripts/platform-audit.sh"
printf 'V020_PLATFORM_TESTS_PASS=True\n'
