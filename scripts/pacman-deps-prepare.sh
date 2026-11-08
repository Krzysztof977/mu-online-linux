#!/usr/bin/env bash
# Pacman dependency preparation for the verified CachyOS recipe.
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
# Detecting pacman alone does not authorize the CachyOS package recipe.
if [[ "$mode" == --install && "$MU_PKG_RECIPE" != cachyos-v020 ]]; then
    printf 'ERROR: automatic pacman package recipe is validated only on CachyOS.\n' >&2
    printf 'NEXT: use assisted manual dependency preparation for this distribution.\n' >&2
    exit 2
fi
if ! pacman-conf --repo-list | grep -Fxq multilib; then
    printf 'ERROR: pacman multilib is not enabled. No installation attempted.\n' >&2
    exit 2
fi

echo
echo '=== PACMAN DEPENDENCY PLAN (LOCAL DATABASE) ==='
mu_pacman_roots
if ! mu_pacman_audit; then
    echo 'ERROR: some roots are unavailable in the local pacman database.'
    echo 'Review repositories and package names. Do not use pacman -Sy as a workaround.'
    exit 2
fi

if (( ${#MU_PACMAN_MISSING[@]} == 0 )); then
    echo
    echo 'PACMAN_DEPENDENCIES_ALREADY_INSTALLED=True'
    echo '=== INDEPENDENT BUILD ENVIRONMENT CHECK ==='
    bash "$SCRIPT_DIR/build-env-audit.sh"
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
    echo 'To install after reviewing the plan: bash scripts/pacman-deps-prepare.sh --install'
    exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    echo 'ERROR: --install requires an interactive terminal. Nothing installed.' >&2
    exit 3
fi

echo
echo 'Only missing package roots from the validated CachyOS recipe will be requested.'
echo 'Pacman will show its own transaction and ask for confirmation.'

echo
echo '=== INSTALL MISSING DEPENDENCIES ==='
if (( EUID == 0 )); then
    pacman -S --needed -- "${MU_PACMAN_MISSING[@]}"
else
    command -v sudo >/dev/null 2>&1 || {
        echo 'ERROR: sudo is not installed. No transaction started.' >&2
        exit 2
    }
    sudo pacman -S --needed -- "${MU_PACMAN_MISSING[@]}"
fi

echo
echo '=== RECHECK INSTALLED ROOTS ==='
mu_pacman_audit || exit 1
if (( ${#MU_PACMAN_MISSING[@]} != 0 )); then
    echo 'ERROR: dependency transaction finished but package roots are still missing.' >&2
    exit 1
fi

echo
echo '=== INDEPENDENT BUILD ENVIRONMENT CHECK ==='
bash "$SCRIPT_DIR/build-env-audit.sh"
echo 'V020_PACMAN_DEPS_PREPARED=True'
