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
check cachyos_no_version cachyos arch '' verified pacman
check cachyos_explicit_rolling_version cachyos arch rolling unverified pacman
# Real CachyOS os-release has BUILD_ID=rolling but no VERSION_ID.
printf 'NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\nBUILD_ID=rolling\n' > "$TMP/os-release"
bash "$ROOT/scripts/platform-audit.sh" "$TMP/os-release" > "$TMP/report"
grep -Fx 'DISTRIBUTION_ID=cachyos' "$TMP/report" > /dev/null
grep -Fx 'DISTRIBUTION_VERSION=' "$TMP/report" > /dev/null
grep -Fx 'PACKAGE_MANAGER_CANDIDATE=pacman' "$TMP/report" > /dev/null
grep -Fx 'DISTRIBUTION_STATUS=verified' "$TMP/report" > /dev/null
echo 'PASS cachyos_no_version_id'
# Also allow operating systems without optional ID_LIKE.
printf 'ID=custom\nVERSION_ID=1\n' > "$TMP/os-release"
bash "$ROOT/scripts/platform-audit.sh" "$TMP/os-release" > "$TMP/report"
grep -Fx 'DISTRIBUTION_LIKE=' "$TMP/report" > /dev/null
grep -Fx 'PACKAGE_MANAGER_CANDIDATE=none' "$TMP/report" > /dev/null
echo 'PASS custom_no_id_like'

# The status must not be conferred to generic Arch or arbitrary ID_LIKE.
printf 'ID=arch\nID_LIKE=\n' > "$TMP/os-release"
bash "$ROOT/scripts/platform-audit.sh" "$TMP/os-release" > "$TMP/report"
grep -Fx 'DISTRIBUTION_STATUS=unverified' "$TMP/report" > /dev/null
echo 'PASS generic_arch_remains_unverified'

check arch arch '' rolling unverified pacman
check derivative unknown 'arch linux' rolling unverified pacman
check unknown unknown '' 1 unverified none
bash -n "$ROOT/scripts/lib/platform-detect.sh"
bash -n "$ROOT/scripts/platform-audit.sh"
printf 'V020_PLATFORM_TESTS_PASS=True\n'
