#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform-detect.sh
. "$SCRIPT_DIR/lib/platform-detect.sh"
mu_detect_platform "${1:-/etc/os-release}"
mu_platform_report
printf 'V020_PLATFORM_DISCOVERY_PASS=True\n'
