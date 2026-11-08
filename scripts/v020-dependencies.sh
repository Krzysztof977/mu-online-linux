#!/usr/bin/env bash
# Experimental MU Online Linux v0.2.0 dependency dispatcher.
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

# A candidate backend is NOT a validated package recipe.
# Only CachyOS has been audited against our experimental pacman roots.
if [[ "$MU_DISTRO_ID" == cachyos && "$MU_PKG_BACKEND" == pacman ]]; then
    echo 'V020_DEPENDENCY_ROUTE=cachyos-pacman'
    if [[ "$mode" == --prepare ]]; then
        exec bash "$SCRIPT_DIR/pacman-deps-prepare.sh" --install
    fi
    exec bash "$SCRIPT_DIR/pacman-deps-prepare.sh" --plan
fi

echo 'V020_DEPENDENCY_ROUTE=manual'
if [[ "$MU_PKG_BACKEND" == dnf || "$MU_PKG_BACKEND" == apt ]]; then
    echo 'NOTICE: the existing v0.1.1 installer retains its verified dnf/apt flow.'
    echo 'NOTICE: this experimental v0.2.0 dispatcher does not alter those recipes.'
fi
if [[ "$mode" == --prepare ]]; then
    exec bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive
fi
exec bash "$SCRIPT_DIR/manual-deps-prepare.sh" --check
