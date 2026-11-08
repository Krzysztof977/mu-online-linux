#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform-detect.sh
. "$SCRIPT_DIR/lib/platform-detect.sh"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/lib/build-env.sh"

mu_detect_platform "${1:-/etc/os-release}" || exit 2
mu_platform_report

if [[ "$(uname -m)" != "x86_64" ]]; then
    printf 'ERROR: Wine build preflight supports x86_64 hosts only\n' >&2
    exit 2
fi

mu_check_build_environment
