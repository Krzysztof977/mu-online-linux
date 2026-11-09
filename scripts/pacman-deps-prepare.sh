#!/usr/bin/env bash
# Pacman dependency preparation for CachyOS and explicitly consented experimental systems.
# --plan is read-only; --install requires a TTY and Pacman's confirmation.
# Distribution consent, when required, is handled by the calling installer.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/platform-detect.sh"
. "$SCRIPT_DIR/lib/pacman-deps.sh"

mode="${1:---plan}"
if (( $# > 1 )); then
    printf 'Usage: %s [--plan|--install]\n' "$0" >&2
    exit 2
fi
case "$mode" in
    --plan|--install) ;;
    *)
        printf 'Usage: %s [--plan|--install]\n' "$0" >&2
        exit 2 ;;
esac

mu_detect_platform
mu_platform_report

if [[ "$MU_HOST_ARCH" != x86_64 ]]; then
    printf 'ERROR: Wine build requires an x86_64 Linux host.\n' >&2
    exit 2
fi
if [[ "$MU_PKG_BACKEND" != pacman ]]; then
    printf 'ERROR: no native pacman backend detected. Use manual dependency setup.\n' >&2
    exit 2
fi
# The main installer obtained CONTINUE for unverified systems.
# Standalone --install still uses Pacman's native confirmation; non-CachyOS
# recipes are experimental and must not be described as verified.
if [[ "$mode" == --install && "$MU_PKG_RECIPE" != cachyos-v020 ]]; then
    if [[ "$MU_PKG_RECIPE" != pacman-experimental-v020 ||
          "$MU_DISTRO_STATUS" != unverified ]]; then
        echo 'ERROR: no supported Pacman dependency route for this platform.' >&2
        exit 2
    fi
    echo 'WARNING: experimental Pacman dependency recipe; MU/GameGuard compatibility is unverified.'
fi
if ! pacman-conf --repo-list | grep -Fxq multilib; then
    printf 'ERROR: pacman multilib is not enabled. No installation attempted.\n' >&2
    exit 2
fi

echo
echo '=== PACMAN DEPENDENCY PLAN (LOCAL DATABASE) ==='
mu_pacman_roots
# Missing package names must not prevent installation of other available
# roots. A manual dependency audit follows if any root remains unavailable.
if mu_pacman_audit; then
    unavailable=0
else
    unavailable=1
    echo 'NOTICE: some package roots are unavailable in the local Pacman database.'
    echo 'Available roots may still be installed; remaining prerequisites require manual setup.'
    echo 'Do not use pacman -Sy as a workaround.'
fi

if (( ${#MU_PACMAN_MISSING[@]} == 0 )); then
    if (( unavailable != 0 )); then
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
    echo
    echo 'PACMAN_DEPENDENCIES_ALREADY_INSTALLED=True'
    echo '=== INDEPENDENT BUILD ENVIRONMENT CHECK ==='
    if ! bash "$SCRIPT_DIR/build-env-audit.sh"; then
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
    echo 'V020_PACMAN_DEPS_PREPARED=True'
    exit 0
fi

echo
printf 'Packages requiring installation: %d\n' "${#MU_PACMAN_MISSING[@]}"
printf '  %s\n' "${MU_PACMAN_MISSING[@]}"
echo
echo 'IMPORTANT: pacman -S uses your current sync database.'
echo 'A full system upgrade is NEVER started by this script.'
echo 'If pacman reports version/signature/404 errors, stop and separately'
echo 'review a full system upgrade with sudo pacman -Syu.'

if [[ "$mode" == --plan ]]; then
    echo
    echo 'READ_ONLY_PLAN=True'
    if (( unavailable != 0 )); then
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
    fi
    echo 'To install after reviewing the plan: bash scripts/pacman-deps-prepare.sh --install'
    exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    echo 'ERROR: --install requires an interactive terminal. Nothing installed.' >&2
    exit 3
fi

echo
echo 'Only available, missing package roots from the detected Pacman recipe will be requested.'
echo 'Pacman will show its own transaction and ask for confirmation.'

echo
echo '=== INSTALL MISSING DEPENDENCIES ==='
if (( EUID == 0 )); then
    if ! pacman -S --needed -- "${MU_PACMAN_MISSING[@]}"; then
        echo 'NOTICE: Pacman could not install all available package roots.'
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo 'NOTICE: sudo is unavailable; manual dependency setup required.'
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
    if ! sudo pacman -S --needed -- "${MU_PACMAN_MISSING[@]}"; then
        echo 'NOTICE: Pacman could not install all available package roots.'
        echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
fi

echo
echo '=== RECHECK INSTALLED ROOTS ==='
if ! mu_pacman_audit; then
    echo 'NOTICE: some package roots remain unavailable after the transaction.'
    echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
    exit 4
fi
if (( ${#MU_PACMAN_MISSING[@]} != 0 )); then
    echo 'NOTICE: package roots are still missing after the transaction.'
    echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
    exit 4
fi

echo
echo '=== INDEPENDENT BUILD ENVIRONMENT CHECK ==='
if ! bash "$SCRIPT_DIR/build-env-audit.sh"; then
    echo 'PACMAN_MANUAL_FALLBACK_REQUIRED=True'
    exit 4
fi
echo 'V020_PACMAN_DEPS_PREPARED=True'
