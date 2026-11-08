#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/consent.sh
. "$ROOT/scripts/lib/consent.sh"

for token in CONTINUE Continue continue cOnTiNuE; do
    mu_consent_matches "$token" CONTINUE
done
for token in INSTALL Install install iNsTaLl; do
    mu_consent_matches "$token" INSTALL
done
for token in "" " " "CONTINUE " " CONTINUE" "CONTINUES" "YES" "INSTALL "; do
    if mu_consent_matches "$token" CONTINUE; then
        echo "ERROR: unexpectedly approved CONTINUE variant: <$token>" >&2
        exit 1
    fi
done
for token in "" " " "INSTALL " " INSTALL" "INSTALLS" "YES" "CONTINUE"; do
    if mu_consent_matches "$token" INSTALL; then
        echo "ERROR: unexpectedly approved INSTALL variant: <$token>" >&2
        exit 1
    fi
done

bash -n "$ROOT/scripts/install.sh"
bash -n "$ROOT/scripts/manual-deps-prepare.sh"
bash -n "$ROOT/scripts/pacman-deps-prepare.sh"
echo 'V020_CASE_INSENSITIVE_CONSENT_TEST_PASS=True'
