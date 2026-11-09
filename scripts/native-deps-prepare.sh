#!/usr/bin/env bash
# Experimental native DNF/APT dependency helper; full installer owns consent.
# --check is read-only; --install requires an interactive terminal.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/platform-detect.sh"
. "$SCRIPT_DIR/lib/native-deps.sh"

if (( $# != 2 )); then
    echo 'Usage: native-deps-prepare.sh [dnf|apt] [--check|--install]' >&2
    exit 2
fi
backend="$1"
mode="$2"
case "$backend:$mode" in
    dnf:--check|apt:--check|dnf:--install|apt:--install) ;;
    *)
        echo 'Usage: native-deps-prepare.sh [dnf|apt] [--check|--install]' >&2
        exit 2 ;;
esac

mu_detect_platform
mu_platform_report

if [[ "$MU_HOST_ARCH" != x86_64 ||
      "$MU_PKG_BACKEND" != "$backend" ]]; then
    echo 'ERROR: native package backend or x86_64 architecture mismatch.' >&2
    exit 2
fi

if [[ "$mode" == --check ]]; then
    echo 'READ_ONLY_NATIVE_DEPENDENCY_AUDIT=True'
    exec bash "$SCRIPT_DIR/build-env-audit.sh"
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    echo 'ERROR: native package installation requires an interactive terminal.' >&2
    exit 3
fi

run_root()
{
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo 'NOTICE: sudo unavailable; manual dependency setup required.' >&2
        return 127
    fi
}

echo 'WARNING: unverified distributions may have different package names.'
echo 'A failed transaction or unavailable package requires manual follow-up.'

if [[ "$backend" == dnf ]]; then
    echo 'NATIVE_DNF_RECIPE_SELECTED=True'
    if ! run_root dnf install -y "${FEDORA_PACKAGES[@]}"; then
        echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
else
    if [[ "$(dpkg --print-architecture)" != amd64 ]]; then
        echo 'NOTICE: the APT recipe requires an amd64 host.'
        echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
    if ! dpkg --print-foreign-architectures | grep -Fxq i386; then
        if ! run_root dpkg --add-architecture i386; then
            echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
            exit 4
        fi
    fi
    if ! dpkg --print-foreign-architectures | grep -Fxq i386; then
        echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
    echo 'NATIVE_APT_RECIPE_SELECTED=True'
    if ! run_root env DEBIAN_FRONTEND=noninteractive apt-get update ||
       ! run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${UBUNTU_PACKAGES[@]}"; then
        echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
        exit 4
    fi
fi

if ! bash "$SCRIPT_DIR/build-env-audit.sh"; then
    echo 'NATIVE_MANUAL_FALLBACK_REQUIRED=True'
    exit 4
fi

echo 'V020_NATIVE_DEPS_PREPARED=True'
