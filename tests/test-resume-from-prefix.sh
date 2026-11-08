#!/usr/bin/env bash
# Non-mutating regression coverage for resuming from an existing Wine prefix.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$SCRIPT"
echo 'V020_RESUME_SYNTAX_PASS=True'

bash "$SCRIPT" --help >"$TMP/help"
grep -Fq -- '--resume-from-prefix' "$TMP/help"
echo 'V020_RESUME_HELP_PASS=True'

for args in \
  '--resume-from-prefix --deps-only' \
  '--resume-from-prefix --configure-only' \
  '--resume-from-prefix --build-only' \
  '--resume-from-prefix --runtime-only' \
  '--resume-from-prefix --prefix-only' \
  '--resume-from-prefix --jobs 2'
do
    set +e
    bash "$SCRIPT" $args --base "$TMP/work-must-not-exist" \
        </dev/null >"$TMP/error" 2>&1
    rc=$?
    set -e
    test "$rc" -ne 0
    test ! -e "$TMP/work-must-not-exist"
done
echo 'V020_RESUME_INVALID_OPTIONS_PASS=True'

# Missing official installer must be refused before touching the prefix.
set +e
bash "$SCRIPT" --resume-from-prefix \
    --installer "$TMP/nonexistent.exe" \
    --base "$TMP/work-must-not-exist" </dev/null \
    >"$TMP/missing" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'installer does not exist' "$TMP/missing"
test ! -e "$TMP/work-must-not-exist"
echo 'V020_RESUME_MISSING_INSTALLER_GUARD_PASS=True'

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]).read_text()
entry=t.index('if [ "$PREFIX_ONLY" -eq 1 ] || [ "$RESUME_FROM_PREFIX" -eq 1 ]; then')
legacy=t.index('log "Platform preflight"')
skip=t.index('fi # V020_PREFIX_ONLY_BYPASS_PREVIOUS_INSTALL_STAGES')
prefix_begin=t.index('if [ "$RESUME_FROM_PREFIX" -eq 0 ]; then')
prefix_end=t.index('fi # V020_SKIP_PREFIX_INITIALIZATION_WHEN_RESUMING')
mu=t.index('# === MU_INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_BEGIN ===')
assert entry < legacy < skip < prefix_begin < prefix_end < mu
segment=t[entry:legacy]
for required in (
    'V020_EXISTING_PREFIX_PRISTINE=True',
    'V020_EXISTING_RUNTIME_VERIFIED=True',
    'prefix already exists; --prefix-only must never overwrite it',
    'MU is already present; refusing to repeat official installation',
    'existing prefix system32 architecture mismatch',
    'existing prefix syswow64 architecture mismatch',
    'cmp -s -- "$BUILD/$BUILD_REL" "$RUNTIME/$RUNTIME_REL"',
    'PROGRESS_DONE=6',
):
    assert required in segment, required
assert 'progress_stage_start "Create Wine prefix"' in t[prefix_begin:prefix_end]
assert 'progress_stage_start "Install MU Online"' in t[mu:]
print('V020_RESUME_RUNTIME_PREFIX_REUSE_STATIC_PASS=True')
PY
