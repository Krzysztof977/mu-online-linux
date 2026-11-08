#!/usr/bin/env bash
# Dry-run safety tests on CachyOS: fake package manager, no root, no mutation.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/scripts/pacman-deps-prepare.sh"

if [[ "$(sed -n 's/^ID=//p' /etc/os-release | head -n1)" != cachyos ]]; then
    echo 'SKIP: integration mocks run on CachyOS only'
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Q) [[ "${2:-}" == pacman ]] ;;
    -Qq) [[ "${2:-}" == pacman ]] ;;
    -Si) exit 0 ;;
    -S|-Sy|-Syu|-Syy|-Syyu)
        echo 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' >&2
        exit 99 ;;
    *) exit 98 ;;
esac
EOF
cat > "$TMP/bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == --repo-list ]] || exit 98
printf 'core\nextra\nmultilib\n'
EOF
chmod 700 "$TMP/bin/pacman" "$TMP/bin/pacman-conf"

# Planning must not invoke installation.
env PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/pacman-deps-prepare.sh" --plan \
    >"$TMP/plan.log" 2>&1
grep -Fxq 'READ_ONLY_PLAN=True' "$TMP/plan.log"
grep -Fq 'PACMAN_ROOTS_AVAILABLE=40' "$TMP/plan.log"
! grep -Fq 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' "$TMP/plan.log"
echo 'V020_PACMAN_PLAN_NO_MUTATION_PASS=True'

# --install must refuse noninteractive stdin before package changes.
set +e
env PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/pacman-deps-prepare.sh" --install \
    </dev/null >"$TMP/install.log" 2>&1
rc=$?
set -e
test "$rc" -eq 3
grep -Fq 'requires an interactive terminal' "$TMP/install.log"
! grep -Fq 'UNSAFE_PACKAGE_TRANSACTION_ATTEMPT' "$TMP/install.log"
echo 'V020_PACMAN_NONINTERACTIVE_GUARD_PASS=True'
