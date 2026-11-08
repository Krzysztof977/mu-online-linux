#!/usr/bin/env bash
# Read-only regression checks for distro consent and dependency routing.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/scripts/install.sh"
PACMAN="$ROOT/scripts/pacman-deps-prepare.sh"
MANUAL="$ROOT/scripts/manual-deps-prepare.sh"
DISPATCH="$ROOT/scripts/v020-dependencies.sh"

for script in "$INSTALL" "$PACMAN" "$MANUAL" "$DISPATCH"; do
    bash -n "$script"
done
echo 'V020_ROUTING_SYNTAX_PASS=True'

# One distribution-level consent in the normal installer, plus the separate
# standalone prefix/resume modes. No helper prompts a second time.
grep -Fq 'Type CONTINUE to proceed with experimental installation:' "$INSTALL"
! grep -Fq 'Type INSTALL to allow a pacman dependency transaction:' "$PACMAN"
! grep -Fq 'Type CONTINUE to enter assisted-manual setup:' "$MANUAL"
! grep -Fq 'CONFIRM EXPERIMENTAL PACKAGE TRANSACTION' "$PACMAN"
echo 'V020_SINGLE_CONSENT_PASS=True'

# Never authorize CachyOS package names solely because pacman is installed.
grep -Fq '[ "$MU_PKG_RECIPE" = cachyos-v020 ]' "$INSTALL"
grep -Fq '"$MU_PKG_RECIPE" != cachyos-v020' "$PACMAN"
grep -Fq '"$MU_PKG_RECIPE" == cachyos-v020' "$DISPATCH"
echo 'V020_RECIPE_GUARD_PASS=True'

# The manual fallback loops until its independent build audit passes, or the
# user quits; Enter retries the audit without package-manager writes.
grep -Fq 'while :; do' "$MANUAL"
grep -Fq 'if bash "$SCRIPT_DIR/build-env-audit.sh"; then' "$MANUAL"
grep -Fq "read -r -p 'Press ENTER to recheck, or Q to quit: ' choice" "$MANUAL"
grep -Fq 'MANUAL_DEPENDENCIES_READY=True' "$MANUAL"
echo 'V020_MANUAL_RECHECK_FLOW_PASS=True'

# Native Pacman confirmation and dry-run protection remain in place.
grep -Fq 'pacman -S --needed -- "${MU_PACMAN_MISSING[@]}"' "$PACMAN"
grep -Fq 'READ_ONLY_PLAN=True' "$PACMAN"
grep -Fq 'requires an interactive terminal' "$PACMAN"
echo 'V020_PACMAN_NATIVE_CONFIRMATION_PASS=True'
