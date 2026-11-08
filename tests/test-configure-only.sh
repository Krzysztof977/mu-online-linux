#!/usr/bin/env bash
# v0.2.0 configure-only safety regression: no Wine downloads/builds executed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$SCRIPT"
echo 'V020_CONFIGURE_ONLY_SYNTAX_PASS=True'

bash "$SCRIPT" --help >"$TMP/help.log"
grep -Fq -- '--configure-only' "$TMP/help.log"
grep -Fq -- '--deps-only' "$TMP/help.log"
echo 'V020_CONFIGURE_ONLY_HELP_PASS=True'

# Conflicting modes stop before any source or workspace operations.
BASE="$TMP/must-not-exist"
set +e
bash "$SCRIPT" --deps-only --configure-only --base "$BASE" \
    </dev/null >"$TMP/conflict.log" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq -- '--deps-only and --configure-only cannot be combined' "$TMP/conflict.log"
test ! -e "$BASE"
echo 'V020_CONFIGURE_ONLY_MODE_CONFLICT_PASS=True'

# Source-order invariant: exit on configure-only success precedes ALL build
# and runtime stages. The test only inspects script text, never runs Wine.
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
checkpoint = text.index('if [ "$CONFIGURE_ONLY" -eq 1 ]; then\n    printf')
build = text.index('# === MU_INSTALLER_STAGE_2D_BUILD_BEGIN ===')
install = text.index('# === MU_INSTALLER_STAGE_2E_RUNTIME_INSTALL_BEGIN ===')
assert checkpoint < build < install
assert 'V020_WINE_CONFIGURE_ONLY_PASS=True' in text[checkpoint:build]
assert "exit 0" in text[checkpoint:build]
print("V020_CONFIGURE_ONLY_BEFORE_BUILD_PASS=True")
PY
