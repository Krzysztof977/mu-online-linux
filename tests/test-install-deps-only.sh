#!/usr/bin/env bash
# End-to-end validation of the read-only installer dependency gate.
# Never downloads Wine, creates prefixes, or starts system package managers.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
bash -n "$SCRIPT"
echo 'V020_INSTALLER_SYNTAX_PASS=True'

# The following checks are intended for the prepared CachyOS VM. On a
# fresh VM an independent audit is expected to report missing packages.
. /etc/os-release
if [[ "${ID:-}" != cachyos ]]; then
    echo 'V020_CACHYOS_INSTALLER_GATE_SKIPPED=True'
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
BASE="$TMP/must-not-be-created"
bash "$SCRIPT" --deps-only --base "$BASE" >"$TMP/audit.log" 2>&1 || {
    cat "$TMP/audit.log"
    echo 'ERROR: --deps-only failed on prepared CachyOS.' >&2
    exit 1
}
grep -Fxq 'V020_BUILD_ENV_AUDIT_PASS=True' "$TMP/audit.log"
grep -Fxq 'INSTALLER_STAGE_2A_DISTRO_DEPS_PASS=True' "$TMP/audit.log"
grep -Fxq 'V020_INSTALLER_DEPENDENCIES_ONLY_PASS=True' "$TMP/audit.log"
! grep -Fq 'Wine source and patches' "$TMP/audit.log"
! grep -Fq 'Acquire pristine Wine' "$TMP/audit.log"
test ! -e "$BASE"
echo 'V020_INSTALLER_CACHYOS_DEPS_ONLY_PASS=True'

# A preflight must stop before mutating the workspace when the installer
# path is invalid, preserving the original full-install guard.
set +e
bash "$SCRIPT" --installer "$TMP/does-not-exist.exe" --base "$BASE" \
    </dev/null >"$TMP/missing-installer.log" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'installer does not exist' "$TMP/missing-installer.log"
test ! -e "$BASE"
echo 'V020_INSTALLER_MISSING_INSTALLER_GUARD_PASS=True'
