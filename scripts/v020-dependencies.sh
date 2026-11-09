#!/usr/bin/env bash
# MU Online Linux v0.2.0 dependency dispatcher.
# Does NOT invoke the legacy installer, download Wine or install MU.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/platform-detect.sh"

mode="${1:---check}"
if (( $# > 1 )); then
    echo 'Usage: v020-dependencies.sh [--check|--prepare]' >&2
    exit 2
fi
case "$mode" in
    --check|--prepare) ;;
    *)
        echo 'Usage: v020-dependencies.sh [--check|--prepare]' >&2
        exit 2 ;;
esac

mu_detect_platform
mu_platform_report
if [[ "$MU_HOST_ARCH" != x86_64 ]]; then
    echo 'ERROR: this Wine build requires an x86_64 Linux host.' >&2
    exit 2
fi

# --check is read-only. --prepare can modify system packages, and an
# unverified OS must explicitly consent before any transaction.
if [[ "$mode" == --prepare && "$MU_DISTRO_STATUS" != verified ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo 'ERROR: unverified distribution requires interactive confirmation.' >&2
        exit 3
    fi
    . "$SCRIPT_DIR/lib/consent.sh"
    printf 'Unverified distribution: %s\n' "$MU_DISTRO_ID"
    read -r -p 'Type CONTINUE to proceed with experimental installation: ' consent ||
        exit 3
    mu_consent_matches "$consent" CONTINUE || {
        echo 'ERROR: experimental dependency preparation not approved.' >&2
        exit 3
    }
fi

route=""
case "$MU_PKG_BACKEND" in
    pacman)
        if [[ "$MU_PKG_RECIPE" == cachyos-v020 ]]; then
            route="cachyos-pacman"
        else
            route="experimental-pacman"
        fi
        echo "V020_DEPENDENCY_ROUTE=$route"
        if [[ "$mode" == --check ]]; then
            exec bash "$SCRIPT_DIR/pacman-deps-prepare.sh" --plan
        fi
        if bash "$SCRIPT_DIR/pacman-deps-prepare.sh" --install; then
            echo 'V020_DEPENDENCIES_PREPARED=True'
            exit 0
        fi
        ;;
    dnf|apt)
        echo "V020_DEPENDENCY_ROUTE=experimental-$MU_PKG_BACKEND"
        if [[ "$mode" == --check ]]; then
            exec bash "$SCRIPT_DIR/native-deps-prepare.sh" "$MU_PKG_BACKEND" --check
        fi
        if bash "$SCRIPT_DIR/native-deps-prepare.sh" "$MU_PKG_BACKEND" --install; then
            echo 'V020_DEPENDENCIES_PREPARED=True'
            exit 0
        fi
        ;;
    *)
        echo 'V020_DEPENDENCY_ROUTE=manual'
        ;;
esac

# Unknown package manager or incomplete native package transaction.
# Never guess additional package names: audit and prompt the user to
# install missing tools/libraries with their distribution's mechanisms.
echo 'NOTICE: complete missing dependencies manually, then recheck.'
if [[ "$mode" == --prepare ]]; then
    exec bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive
fi
exec bash "$SCRIPT_DIR/manual-deps-prepare.sh" --check
