#!/usr/bin/env bash
# Safety regression: build-only checkpoint must precede runtime installation.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$SCRIPT"
echo 'V020_BUILD_ONLY_SYNTAX_PASS=True'

bash "$SCRIPT" --help >"$TMP/help.log"
grep -Fq -- '--build-only' "$TMP/help.log"
grep -Fq -- '--jobs N' "$TMP/help.log"
echo 'V020_BUILD_ONLY_HELP_PASS=True'

for args in '--build-only --deps-only' '--build-only --configure-only' '--build-only --jobs 0' '--build-only --jobs abc'; do
    # This tests rejection before any workspace modifications.
    set +e
    bash "$SCRIPT" $args --base "$TMP/never-created" </dev/null \
        >"$TMP/invalid.log" 2>&1
    rc=$?
    set -e
    test "$rc" -ne 0
    test ! -e "$TMP/never-created"
done
echo 'V020_BUILD_ONLY_INVALID_OPTIONS_PASS=True'

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]).read_text()
checkpoint=t.index('if [ "$BUILD_ONLY" -eq 1 ]; then\n    printf')
runtime=t.index('# === MU_INSTALLER_STAGE_2E_RUNTIME_INSTALL_BEGIN ===')
assert checkpoint < runtime
assert 'V020_WINE_BUILD_ONLY_PASS=True' in t[checkpoint:runtime]
assert 'exit 0' in t[checkpoint:runtime]
assert 'BUILD_JOBS_OVERRIDE' in t
print('V020_BUILD_ONLY_BEFORE_RUNTIME_PASS=True')
PY
