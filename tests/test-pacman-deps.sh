#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/lib/pacman-deps.sh"

bash -n "$ROOT/scripts/lib/pacman-deps.sh"
bash -n "$ROOT/scripts/pacman-deps-audit.sh"

mu_pacman_roots

test "${#MU_PACMAN_PACKAGES[@]}" -eq 40
printf '%s\n' "${MU_PACMAN_PACKAGES[@]}" | grep -Fxq 'vulkan-headers'
printf '%s\n' "${MU_PACMAN_PACKAGES[@]}" | grep -Fxq 'mingw-w64-gcc'
printf '%s\n' "${MU_PACMAN_PACKAGES[@]}" | grep -Fxq 'lib32-libpulse'
printf '%s\n' "${MU_PACMAN_PACKAGES[@]}" | grep -Fxq 'lib32-alsa-lib'
test "$(printf '%s\n' "${MU_PACMAN_PACKAGES[@]}" | sort -u | wc -l)" -eq "${#MU_PACMAN_PACKAGES[@]}"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -Qq) [[ "$2" == "base-devel" ]] ;;
  -Si) [[ "$2" != "vulkan-headers" ]] ;;
  *) exit 3 ;;
esac
EOF
chmod 700 "$TMP/bin/pacman"
(
    export PATH="$TMP/bin:$PATH"
    set +e
    mu_pacman_audit > "$TMP/report"
    RC=$?
    test "$RC" -eq 1
    grep -Fxq 'PACMAN_ROOTS_INSTALLED=1' "$TMP/report"
    grep -Fxq 'PACMAN_ROOTS_UNAVAILABLE=1' "$TMP/report"
    grep -Fxq 'NOT_FOUND   vulkan-headers' "$TMP/report"
    grep -Fxq 'PACMAN_RECIPE_STATUS=unavailable' "$TMP/report"
)
echo 'V020_PACMAN_RECIPE_NEGATIVE_TEST_PASS=True'
