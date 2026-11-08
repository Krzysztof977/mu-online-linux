#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/manual-deps-prepare.sh"

bash -n "$SCRIPT"
echo 'V020_MANUAL_SYNTAX_PASS=True'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# No attached TTY: must emit an audit report and refuse interactive retries.
set +e
bash "$SCRIPT" --interactive </dev/null > "$TMP/noninteractive.log" 2>&1
rc=$?
set -e

test "$rc" -eq 3
grep -Fq 'MANUAL_NONINTERACTIVE_REFUSED=True' "$TMP/noninteractive.log"
grep -Fq 'BUILD ENVIRONMENT: REQUIRED TOOLS' "$TMP/noninteractive.log"
grep -Fq 'MANUAL_AUDIT_EXIT_STATUS=' "$TMP/noninteractive.log"

echo 'V020_MANUAL_NONINTERACTIVE_GUARD_PASS=True'

# Invalid option must never trigger an audit or mutation.
set +e
bash "$SCRIPT" --unknown </dev/null >"$TMP/invalid.log" 2>&1
rc=$?
set -e
test "$rc" -eq 2
grep -Fq 'Usage:' "$TMP/invalid.log"
echo 'V020_MANUAL_INVALID_OPTION_PASS=True'
