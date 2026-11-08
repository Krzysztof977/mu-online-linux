#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT="mu-online-linux"
VERSION="0.2.0"
TAG="v0.2.0"

OWNER="Krzysztof977"
REPOSITORY="mu-online-linux"

ARCHIVE="${PROJECT}-${VERSION}.tar.gz"
CHECKSUM_FILE="SHA256SUMS"
ARCHIVE_ROOT="${PROJECT}-${VERSION}"

URL_SCHEME="https:"
RELEASE_BASE="${URL_SCHEME}//github.com/${OWNER}/${REPOSITORY}/releases/download/${TAG}"
ARCHIVE_URL="${RELEASE_BASE}/${ARCHIVE}"
CHECKSUM_URL="${RELEASE_BASE}/${CHECKSUM_FILE}"

# Release archive generated from source commit:
# a0318ca5dc665e115b6fd429214bfc79618d9b73
# Using 'git archive HEAD' after this bootstrap commit changes the TAR
# PAX commit metadata, even though bootstrap.sh is excluded. Keep the
# audited release archive rather than regenerating it from the tag.
EXPECTED_SHA256="c0b2e7bdcb900eba9c3aaf6e183e5ac1932ab79e88e3b1aec81df3c7406ea81e"

WORKDIR=""
CLEANUP_DONE=0

cleanup()
{
    local rc=$?

    trap - EXIT HUP INT TERM

    if [[ "$CLEANUP_DONE" -eq 0 ]] &&
       [[ -n "${WORKDIR:-}" ]] &&
       [[ -d "$WORKDIR" ]]
    then
        rm -rf -- "$WORKDIR"
    fi

    CLEANUP_DONE=1
    exit "$rc"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail()
{
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command()
{
    local command_name="$1"

    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Required command not found: ${command_name}"
}

echo "MU Online Linux bootstrap ${VERSION}"
echo

for command_name in \
    curl \
    sha256sum \
    tar \
    mktemp \
    mkdir \
    rm
do
    require_command "$command_name"
done

if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]]
then
    fail "Bootstrap release SHA256 is not finalized."
fi

umask 077

WORKDIR="$(
    mktemp -d \
        "${TMPDIR:-/tmp}/mu-online-linux-bootstrap.XXXXXXXX"
)"

DOWNLOAD_DIR="$WORKDIR/download"
EXTRACT_DIR="$WORKDIR/extract"

mkdir -p \
    "$DOWNLOAD_DIR" \
    "$EXTRACT_DIR"

ARCHIVE_PATH="$DOWNLOAD_DIR/$ARCHIVE"
CHECKSUM_PATH="$DOWNLOAD_DIR/$CHECKSUM_FILE"

echo "Release: ${TAG}"
echo "Downloading release archive..."

curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --retry-delay 1 \
    --connect-timeout 30 \
    --proto '=https' \
    --proto-redir '=https' \
    --output "$ARCHIVE_PATH" \
    "$ARCHIVE_URL"

echo "Downloading release checksum..."

curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --retry-delay 1 \
    --connect-timeout 30 \
    --proto '=https' \
    --proto-redir '=https' \
    --output "$CHECKSUM_PATH" \
    "$CHECKSUM_URL"

echo "Verifying release checksum..."

read -r ACTUAL_SHA256 _ < <(
    sha256sum "$ARCHIVE_PATH"
)

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]
then
    fail "Release archive SHA256 mismatch."
fi

mapfile -t checksum_lines < "$CHECKSUM_PATH"

if [[ "${#checksum_lines[@]}" -ne 1 ]]
then
    fail "Unexpected SHA256SUMS format."
fi

EXPECTED_CHECKSUM_LINE="${EXPECTED_SHA256}  ${ARCHIVE}"

if [[ "${checksum_lines[0]}" != "$EXPECTED_CHECKSUM_LINE" ]]
then
    fail "SHA256SUMS does not match the pinned release digest."
fi

echo "Release checksum verified."

echo "Validating archive paths..."

ARCHIVE_LIST="$(
    tar -tzf "$ARCHIVE_PATH"
)"

member_count=0

while IFS= read -r member
do
    [[ -n "$member" ]] || continue

    member_count=$((member_count + 1))

    case "$member" in
        /*)
            fail "Archive contains an absolute path."
            ;;
    esac

    case "/$member/" in
        */../*)
            fail "Archive contains a parent-directory traversal."
            ;;
    esac

    case "$member" in
        "$ARCHIVE_ROOT"|"$ARCHIVE_ROOT/"|"$ARCHIVE_ROOT/"*)
            ;;
        *)
            fail "Archive contains a path outside ${ARCHIVE_ROOT}."
            ;;
    esac
done <<< "$ARCHIVE_LIST"

if [[ "$member_count" -eq 0 ]]
then
    fail "Release archive is empty."
fi

echo "Extracting verified release..."

tar \
    -xzf "$ARCHIVE_PATH" \
    -C "$EXTRACT_DIR" \
    --no-same-owner \
    --no-same-permissions

INSTALLER_SCRIPT="$EXTRACT_DIR/$ARCHIVE_ROOT/scripts/install.sh"

if [[ ! -f "$INSTALLER_SCRIPT" ]]
then
    fail "Release installer is missing."
fi

if [[ -L "$INSTALLER_SCRIPT" ]]
then
    fail "Release installer must not be a symbolic link."
fi

if [[ ! -x "$INSTALLER_SCRIPT" ]]
then
    fail "Release installer is not executable."
fi

echo
echo "Starting verified MU Online Linux installer..."
echo

set +e

"$INSTALLER_SCRIPT" "$@"
installer_rc=$?

set -e

echo

if [[ "$installer_rc" -eq 0 ]]
then
    echo "Installer completed successfully."
else
    echo "Installer exited with status ${installer_rc}." >&2
fi

exit "$installer_rc"
