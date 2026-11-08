#!/usr/bin/env bash
# Safety tests: the runtime-only checkpoint never starts Wine or make here.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$SCRIPT"
echo 'V020_RUNTIME_ONLY_SYNTAX_PASS=True'
bash "$SCRIPT" --help >"$TMP/help.log"
grep -Fq -- '--runtime-only' "$TMP/help.log"
echo 'V020_RUNTIME_ONLY_HELP_PASS=True'

for args in \
    '--runtime-only --deps-only' \
    '--runtime-only --configure-only' \
    '--runtime-only --build-only'
do
    set +e
    bash "$SCRIPT" $args --base "$TMP/never-created" </dev/null \
        >"$TMP/invalid.log" 2>&1
    rc=$?
    set -e
    test "$rc" -ne 0
    grep -Fq -- '--runtime-only cannot be combined' "$TMP/invalid.log"
    test ! -e "$TMP/never-created"
done
echo 'V020_RUNTIME_ONLY_INVALID_OPTIONS_PASS=True'

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
checkpoint = t.index('if [ "$RUNTIME_ONLY" -eq 1 ]; then\n    printf')
prefix = t.index('# === MU_INSTALLER_STAGE_3A_FRESH_PREFIX_BEGIN ===')
install = t.index('# === MU_INSTALLER_STAGE_2E_RUNTIME_INSTALL_BEGIN ===')
assert install < checkpoint < prefix
assert "V020_WINE_RUNTIME_ONLY_PASS=True" in t[checkpoint:prefix]
assert "exit 0" in t[checkpoint:prefix]
print('V020_RUNTIME_ONLY_BEFORE_PREFIX_PASS=True')
PY
