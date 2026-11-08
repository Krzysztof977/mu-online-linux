#!/usr/bin/env bash
# Prefix-only regression checks: no Wine process is launched by this test.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$SCRIPT"
echo 'V020_PREFIX_ONLY_SYNTAX_PASS=True'
bash "$SCRIPT" --help > "$TMP/help"
grep -Fq -- '--prefix-only' "$TMP/help"
echo 'V020_PREFIX_ONLY_HELP_PASS=True'

for args in \
    '--prefix-only --deps-only' \
    '--prefix-only --configure-only' \
    '--prefix-only --build-only' \
    '--prefix-only --runtime-only' \
    '--prefix-only --jobs 2'
do
    set +e
    bash "$SCRIPT" $args --base "$TMP/no-workspace" </dev/null \
        > "$TMP/invalid" 2>&1
    rc=$?
    set -e
    test "$rc" -ne 0
    test ! -e "$TMP/no-workspace"
done
echo 'V020_PREFIX_ONLY_INVALID_OPTIONS_PASS=True'

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

t = Path(sys.argv[1]).read_text()
entry = t.index('if [ "$PREFIX_ONLY" -eq 1 ]; then\n    log "Reuse existing private Wine runtime')
preflight = t.index('log "Platform preflight"')
skip_end = t.index('fi # V020_PREFIX_ONLY_BYPASS_PREVIOUS_INSTALL_STAGES')
wineboot = t.index('# === MU_INSTALLER_STAGE_3A_FRESH_PREFIX_BEGIN ===')
cutoff = t.index('if [ "$PREFIX_ONLY" -eq 1 ]; then\n    printf')
mu = t.index('# === MU_INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_BEGIN ===')
assert entry < preflight < skip_end < wineboot < cutoff < mu
assert 'exit 0' in t[cutoff:mu]
assert 'V020_WINE_PREFIX_ONLY_PASS=True' in t[cutoff:mu]
assert 'V020_EXISTING_RUNTIME_VERIFIED=True' in t[entry:preflight]
assert '[ ! -e "$PREFIX" ]' in t[entry:preflight]
assert 'cmp -s -- "$BUILD/$BUILD_REL" "$RUNTIME/$RUNTIME_REL"' in t[entry:preflight]
print('V020_PREFIX_ONLY_REUSE_CHECKPOINT_PASS=True')
PY
