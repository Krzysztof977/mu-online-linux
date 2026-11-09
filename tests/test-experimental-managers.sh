#!/usr/bin/env bash
# Isolated, non-mutating experimental manager regression checks.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/scripts/lib" "$TMP/bin"
cp "$ROOT/scripts/pacman-deps-prepare.sh" "$TMP/scripts/"
cp "$ROOT/scripts/native-deps-prepare.sh" "$TMP/scripts/"
cp "$ROOT/scripts/lib/pacman-deps.sh" "$TMP/scripts/lib/"
cp "$ROOT/scripts/lib/native-deps.sh" "$TMP/scripts/lib/"

cat > "$TMP/scripts/lib/platform-detect.sh" <<'EOF'
mu_detect_platform() {
    MU_DISTRO_ID=arch
    MU_DISTRO_STATUS=unverified
    MU_PKG_BACKEND="$MOCK_BACKEND"
    MU_PKG_RECIPE=pacman-experimental-v020
    MU_HOST_ARCH=x86_64
}
mu_platform_report() {
    printf 'DISTRIBUTION_ID=%s\n' "$MU_DISTRO_ID"
    printf 'DISTRIBUTION_STATUS=%s\n' "$MU_DISTRO_STATUS"
    printf 'PACKAGE_MANAGER_BACKEND=%s\n' "$MU_PKG_BACKEND"
}
EOF

cat > "$TMP/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Q) [[ "$2" == pacman ]] ;;
    -Qq) [[ "$2" == pacman ]] ;;
    -Si) [[ "$2" != "$MISSING_PACKAGE" ]] ;;
    -S|-Sy|-Syu|-Syy|-Syyu)
        echo 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' >&2
        exit 99 ;;
    *) exit 98 ;;
esac
EOF
cat > "$TMP/bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == --repo-list ]] || exit 98
printf 'core\nextra\nmultilib\n'
EOF
chmod 700 "$TMP/bin/pacman" "$TMP/bin/pacman-conf"

env MOCK_BACKEND=pacman MISSING_PACKAGE=none PATH="$TMP/bin:$PATH" \
    bash "$TMP/scripts/pacman-deps-prepare.sh" --plan \
    >"$TMP/arch-plan.log" 2>&1
grep -Fxq 'READ_ONLY_PLAN=True' "$TMP/arch-plan.log"
grep -Fxq 'PACMAN_ROOTS_AVAILABLE=40' "$TMP/arch-plan.log"
! grep -Fq 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' "$TMP/arch-plan.log"
echo 'V020_EXPERIMENTAL_ARCH_PLAN_PASS=True'

env MOCK_BACKEND=pacman MISSING_PACKAGE=mingw-w64-gcc PATH="$TMP/bin:$PATH" \
    bash "$TMP/scripts/pacman-deps-prepare.sh" --plan \
    >"$TMP/arch-missing.log" 2>&1
grep -Fxq 'PACMAN_ROOTS_UNAVAILABLE=1' "$TMP/arch-missing.log"
grep -Fxq 'PACMAN_ROOTS_AVAILABLE=39' "$TMP/arch-missing.log"
grep -Fxq 'PACMAN_MANUAL_FALLBACK_REQUIRED=True' "$TMP/arch-missing.log"
! grep -Fq 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' "$TMP/arch-missing.log"
echo 'V020_EXPERIMENTAL_ARCH_MANUAL_FALLBACK_PASS=True'

for backend in pacman dnf apt; do
    script="$TMP/scripts/native-deps-prepare.sh"
    args=("$backend" --install)
    if [[ "$backend" == pacman ]]; then
        script="$TMP/scripts/pacman-deps-prepare.sh"
        args=(--install)
    fi
    set +e
    env MOCK_BACKEND="$backend" MISSING_PACKAGE=none PATH="$TMP/bin:$PATH" \
        bash "$script" "${args[@]}" </dev/null \
        >"$TMP/$backend-install.log" 2>&1
    rc=$?
    set -e
    test "$rc" -eq 3
    grep -Fq 'requires an interactive terminal' "$TMP/$backend-install.log"
    ! grep -Fq 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' "$TMP/$backend-install.log"
done
echo 'V020_EXPERIMENTAL_NATIVE_NONINTERACTIVE_GUARDS_PASS=True'
