#!/usr/bin/env bash
# MU Online Linux v0.2.0 assisted-manual dependency preparation.
# This tool never installs packages or modifies the host.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform-detect.sh
. "$SCRIPT_DIR/lib/platform-detect.sh"

mode="${1:---check}"
if (( $# > 1 )); then
    printf 'Usage: %s [--check|--interactive]\n' "$0" >&2
    exit 2
fi
case "$mode" in
    --check|--interactive) ;;
    *)
        printf 'Usage: %s [--check|--interactive]\n' "$0" >&2
        exit 2 ;;
esac

mu_detect_platform
mu_platform_report

if [[ "$MU_HOST_ARCH" != x86_64 ]]; then
    echo 'ERROR: Wine build requires x86_64 Linux.' >&2
    exit 2
fi

if [[ "$MU_DISTRO_ID" == gentoo ]] &&
   command -v emerge >/dev/null 2>&1; then
    echo 'MANUAL_PACKAGE_MANAGER=portage'
else
    echo 'MANUAL_PACKAGE_MANAGER=unspecified'
fi

# Always offer a noninteractive report, never stall on a prompt in automation.
if [[ "$mode" == --interactive && ( ! -t 0 || ! -t 1 ) ]]; then
    echo 'NOTICE: interactive mode requires a terminal; showing a one-time audit.'
    set +e
    bash "$SCRIPT_DIR/build-env-audit.sh"
    rc=$?
    set -e
    printf 'MANUAL_AUDIT_EXIT_STATUS=%d\n' "$rc"
    echo 'MANUAL_NONINTERACTIVE_REFUSED=True'
    exit 3
fi

# The parent installer requests CONTINUE once on unverified distributions.
# This helper performs no package transactions, so no second consent is needed.
if [[ "$MU_DISTRO_STATUS" != verified ]]; then
    echo 'NOTICE: build prerequisites alone do not verify MU/GameGuard compatibility.'
fi

attempt=0
while :; do
    ((attempt+=1))
    printf '\n=== INDEPENDENT WINE BUILD AUDIT: ATTEMPT %d ===\n' "$attempt"

    if bash "$SCRIPT_DIR/build-env-audit.sh"; then
        echo
        echo 'MANUAL_DEPENDENCIES_READY=True'
        echo 'NOTE: no Wine compilation or MU installation was performed.'
        exit 0
    fi

    echo
    echo 'MANUAL_DEPENDENCIES_READY=False'
    echo 'Install the missing compiler tools, development headers and libraries'
    echo 'using your distribution package manager, then rerun this check.'
    if [[ "$MU_DISTRO_ID" == gentoo ]]; then
        echo 'Gentoo: use Portage and review USE flags, ABI_X86 and multilib settings.'
        echo 'No package names or emerge commands are guessed by this script.'
    fi

    if [[ "$mode" == --check ]]; then
        echo 'RECHECK_COMMAND=bash scripts/manual-deps-prepare.sh --check'
        exit 1
    fi

    echo
    echo '[ENTER] Recheck build dependencies'
    echo '[Q] Quit without installing anything'
    read -r -p 'Press ENTER to recheck, or Q to quit: ' choice || exit 3
    case "$choice" in
        [Rr]|'') ;;
        [Qq])
            echo 'MANUAL_SETUP_QUIT=True'
            exit 3 ;;
        *)
            echo 'Invalid choice; enter R or Q.' ;;
    esac
done
