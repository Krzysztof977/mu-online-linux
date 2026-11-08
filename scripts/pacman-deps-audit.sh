#!/usr/bin/env bash
# v0.2.0 experimental pacman dependency audit; never modifies the system.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/platform-detect.sh"
. "$SCRIPT_DIR/lib/pacman-deps.sh"

mu_detect_platform
mu_platform_report

if [[ "$MU_PKG_BACKEND" != pacman ]]; then
    printf 'ERROR: native pacman backend was not validated\n' >&2
    exit 2
fi
if [[ "$MU_HOST_ARCH" != x86_64 ]]; then
    printf 'ERROR: only x86_64 is supported for the Wine build\n' >&2
    exit 2
fi

if [[ "$MU_DISTRO_ID" != cachyos && "$MU_DISTRO_ID" != arch ]]; then
    printf 'NOTICE: this dependency recipe is experimentally tested only on CachyOS/Arch\n'
fi

if ! pacman-conf --repo-list | grep -Fxq multilib; then
    printf 'ERROR: multilib repository is disabled\n' >&2
    exit 2
fi

mu_pacman_roots
mu_pacman_audit

echo
echo 'V020_PACMAN_RECIPE_AUDIT_PASS=True'
