#!/usr/bin/env bash

set -euo pipefail

# MU Online Global on Linux
# Verified reference platform: Fedora 44 x86_64
# Wine base: 11.6
#
# This installer does not redistribute or patch MU Online or GameGuard.
# The official MU installer must be supplied separately by the user.
#
# GGKernel64.sys is not bundled, copied, restored or injected.
# GameGuard remains responsible for supplying and managing its driver file.

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

REPO_ROOT="$(
    cd -- "$SCRIPT_DIR/.." &&
    pwd
)"

WINE_VERSION="11.6"

WINE_ARCHIVE_NAME="wine-${WINE_VERSION}.tar.xz"
WINE_SOURCE_URL="https:""//dl.winehq.org/wine/source/11.x/${WINE_ARCHIVE_NAME}"

WINE_ARCHIVE_SHA256="d49d166975478f609e6a9cdbda0a07c65a3b795e061fc454d3f1034c828d19e0"

PATCH_NAMES=(
    "0001-ntdll-ntloaddriver-scm.patch"
    "0002-ntdll-wow64-stack-semantics.patch"
    "0003-kernelbase-urlescape-sentinel.patch"
    "0004-ntoskrnl-gameguard-compat.patch"
)

PATCH_SHA256=(
    "128398b6cc9a8be12771df8636e6ab5db96dc68c2ed4dc275045211354e79ab8"
    "507dcf28948909a3d869b58f5ff1aa1272a1c6b6abeb2d42e6350c6ae9cad8a0"
    "98478fac80966bffac650a76e870ba1a39a809eb5d20d783dd8486cb9b628572"
    "d40695dcc32b3f2f5343e4bf1eef5ae7a212da4fdb0f454209f0c1d833721399"
)

DEFAULT_BASE="$HOME/.local/share/mu-online-linux"

BASE="$DEFAULT_BASE"
INSTALLER=""
SKIP_DEPS=0
DEPS_ONLY=0
CONFIGURE_ONLY=0
BUILD_ONLY=0
RUNTIME_ONLY=0
PREFIX_ONLY=0
RESUME_FROM_PREFIX=0
BUILD_JOBS_OVERRIDE=""

usage()
{
    cat <<USAGE
Usage:
  $0 --installer /path/to/MU-installer.exe [options]

Options:
  --installer PATH   Official MU Online Windows installer.
  --base PATH        Installation workspace.
                     Default: $DEFAULT_BASE
  --skip-deps        Do not run system dependency installation.
  --deps-only        Read-only dependency validation; no MU installer needed.
  --configure-only   Verify/patch Wine source and run configure only.
                     No MU installer, build, runtime or prefix required.
  --build-only       Configure and compile Wine without installing runtime or MU.
  --runtime-only     Install and verify private Wine without creating prefix or MU.
  --prefix-only      Initialize/validate pristine WoW64 prefix using installed Wine.
  --resume-from-prefix
                     Reuse verified Wine and prefix, install official MU.
  --jobs N           Parallel make jobs (default: nproc).
  -h, --help         Show this help.

The script installs a private Wine runtime and a separate Wine prefix.
It does not replace the system Wine installation.
USAGE
}

die()
{
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log()
{
    printf '\n==> %s\n' "$*"
}

# === MU_INSTALLER_PROGRESS_UI_V1_BEGIN ===

PROGRESS_TOTAL=10
PROGRESS_DONE=0
PROGRESS_CURRENT=""
PROGRESS_BAR_WIDTH=20

progress_bar_text()
{
    local DONE="$1"
    local FILLED
    local EMPTY
    local BAR=""
    local I

    FILLED="$((DONE * PROGRESS_BAR_WIDTH / PROGRESS_TOTAL))"
    EMPTY="$((PROGRESS_BAR_WIDTH - FILLED))"

    for ((I = 0; I < FILLED; I++)); do
        BAR+="█"
    done

    for ((I = 0; I < EMPTY; I++)); do
        BAR+="░"
    done

    printf '%s' "$BAR"
}

progress_render()
{
    local SYMBOL="$1"
    local LABEL="$2"
    local PERCENT
    local BAR

    PERCENT="$((PROGRESS_DONE * 100 / PROGRESS_TOTAL))"
    BAR="$(progress_bar_text "$PROGRESS_DONE")"

    printf '[%s] %2d/%d %3d%%  %s %s\n' \
        "$BAR" \
        "$PROGRESS_DONE" \
        "$PROGRESS_TOTAL" \
        "$PERCENT" \
        "$SYMBOL" \
        "$LABEL"
}

progress_begin()
{
    printf '\n'
    printf '%s\n' 'Installation progress'
}

progress_stage_start()
{
    local LABEL="$1"

    PROGRESS_CURRENT="$LABEL"

    printf '\n'

    progress_render \
        '▶' \
        "$LABEL"
}

progress_stage_complete()
{
    [ "$PROGRESS_DONE" -lt "$PROGRESS_TOTAL" ] ||
        die "installation progress exceeded configured stage count"

    PROGRESS_DONE="$((PROGRESS_DONE + 1))"
    PROGRESS_CURRENT=""
}

progress_assert_complete()
{
    [ "$PROGRESS_DONE" -eq "$PROGRESS_TOTAL" ] ||
        die "installation progress incomplete: ${PROGRESS_DONE}/${PROGRESS_TOTAL}"

    printf '\n'

    progress_render \
        '✓' \
        'Installation complete'

    printf 'INSTALL_PROGRESS_COMPLETE=True\n'
}

# === MU_INSTALLER_BUILD_HEARTBEAT_V1_BEGIN ===

progress_format_hms()
{
    local TOTAL="$1"
    local HOURS
    local MINUTES
    local SECONDS

    HOURS="$((TOTAL / 3600))"
    MINUTES="$(((TOTAL % 3600) / 60))"
    SECONDS="$((TOTAL % 60))"

    printf '%02d:%02d:%02d' \
        "$HOURS" \
        "$MINUTES" \
        "$SECONDS"
}

progress_build_process_counts()
{
    local ROOT_PID="$1"

    if ! command -v ps >/dev/null 2>&1; then
        printf '%s' \
            'make=? cc1=? mingw=? winebuild=?'
        return 0
    fi

    ps -eo pid=,ppid=,comm=,args= 2>/dev/null |
        awk -v root="$ROOT_PID" '
            {
                pid[NR] = $1
                parent[NR] = $2
                command[NR] = $3
                argv0[NR] = $4
            }

            END {
                seen[root] = 1
                changed = 1

                while (changed) {
                    changed = 0

                    for (i = 1; i <= NR; i++) {
                        if (seen[parent[i]] &&
                            !seen[pid[i]]) {
                            seen[pid[i]] = 1
                            changed = 1
                        }
                    }
                }

                make_count = 0
                cc1_count = 0
                mingw_count = 0
                winebuild_count = 0

                for (i = 1; i <= NR; i++) {
                    if (!seen[pid[i]]) {
                        continue
                    }

                    if (command[i] == "make" ||
                        command[i] == "gmake") {
                        make_count++
                    }

                    if (command[i] == "cc1" ||
                        command[i] == "cc1plus") {
                        cc1_count++
                    }

                    if (argv0[i] ~ /(^|\/)(x86_64|i686)-w64-mingw32-/) {
                        mingw_count++
                    }

                    if (command[i] == "winebuild") {
                        winebuild_count++
                    }
                }

                printf \
                    "make=%d cc1=%d mingw=%d winebuild=%d", \
                    make_count, \
                    cc1_count, \
                    mingw_count, \
                    winebuild_count
            }
        '
}

progress_build_heartbeat()
{
    local ROOT_PID="$1"
    local START_EPOCH="$2"
    local LOG_FILE="$3"

    local NOW
    local ELAPSED
    local ELAPSED_TEXT
    local LOG_MTIME
    local LOG_AGE
    local LOG_TEXT
    local COUNTS
    local NEXT_TEXT_REPORT=0
    local FRAME=0

    local SPINNER=(
        '⠋'
        '⠙'
        '⠹'
        '⠸'
        '⠼'
        '⠴'
        '⠦'
        '⠧'
        '⠇'
        '⠏'
    )

    while kill -0 "$ROOT_PID" 2>/dev/null
    do
        NOW="$(date +%s)"
        ELAPSED="$((NOW - START_EPOCH))"

        if [ "$ELAPSED" -lt 0 ]; then
            ELAPSED=0
        fi

        ELAPSED_TEXT="$(
            progress_format_hms "$ELAPSED"
        )"

        if [ -e "$LOG_FILE" ]; then
            LOG_MTIME="$(
                stat -c %Y "$LOG_FILE" 2>/dev/null ||
                    printf '%s\n' "$NOW"
            )"

            LOG_AGE="$((NOW - LOG_MTIME))"

            if [ "$LOG_AGE" -lt 0 ]; then
                LOG_AGE=0
            fi

            LOG_TEXT="${LOG_AGE}s"
        else
            LOG_TEXT="-"
        fi

        COUNTS="$(
            progress_build_process_counts "$ROOT_PID"
        )"

        if [ -t 1 ] &&
           [ "${TERM:-dumb}" != "dumb" ]
        then
            printf '\r\033[2K  %s Build Wine | %s | log %s | %s' \
                "${SPINNER[$FRAME]}" \
                "$ELAPSED_TEXT" \
                "$LOG_TEXT" \
                "$COUNTS"

            FRAME="$(((FRAME + 1) % ${#SPINNER[@]}))"
        else
            if [ "$NOW" -ge "$NEXT_TEXT_REPORT" ]; then
                printf \
                    'BUILD_HEARTBEAT elapsed=%s log_age=%s %s\n' \
                    "$ELAPSED_TEXT" \
                    "$LOG_TEXT" \
                    "$COUNTS"

                NEXT_TEXT_REPORT="$((NOW + 30))"
            fi
        fi

        sleep 2
    done
}

progress_build_heartbeat_finish()
{
    if [ -t 1 ] &&
       [ "${TERM:-dumb}" != "dumb" ]
    then
        printf '\r\033[2K'
        printf '\n'
    fi
}

# === MU_INSTALLER_BUILD_HEARTBEAT_V1_END ===

# === MU_INSTALLER_RUNTIME_INSTALL_HEARTBEAT_V1_BEGIN ===

progress_install_process_counts()
{
    local ROOT_PID="$1"

    if ! command -v ps >/dev/null 2>&1; then
        printf '%s' \
            'make=? install=?'
        return 0
    fi

    ps -eo pid=,ppid=,comm= 2>/dev/null |
        awk -v root="$ROOT_PID" '
            {
                pid[NR] = $1
                parent[NR] = $2
                command[NR] = $3
            }

            END {
                seen[root] = 1
                changed = 1

                while (changed) {
                    changed = 0

                    for (i = 1; i <= NR; i++) {
                        if (seen[parent[i]] &&
                            !seen[pid[i]]) {
                            seen[pid[i]] = 1
                            changed = 1
                        }
                    }
                }

                make_count = 0
                install_count = 0

                for (i = 1; i <= NR; i++) {
                    if (!seen[pid[i]]) {
                        continue
                    }

                    if (command[i] == "make" ||
                        command[i] == "gmake") {
                        make_count++
                    }

                    if (command[i] == "install") {
                        install_count++
                    }
                }

                printf \
                    "make=%d install=%d", \
                    make_count, \
                    install_count
            }
        '
}

progress_install_heartbeat()
{
    local ROOT_PID="$1"
    local START_EPOCH="$2"
    local LOG_FILE="$3"

    local NOW
    local ELAPSED
    local ELAPSED_TEXT
    local LOG_MTIME
    local LOG_AGE
    local LOG_TEXT
    local COUNTS
    local NEXT_TEXT_REPORT=0
    local FRAME=0

    local SPINNER=(
        '⠋'
        '⠙'
        '⠹'
        '⠸'
        '⠼'
        '⠴'
        '⠦'
        '⠧'
        '⠇'
        '⠏'
    )

    while kill -0 "$ROOT_PID" 2>/dev/null
    do
        NOW="$(date +%s)"
        ELAPSED="$((NOW - START_EPOCH))"

        if [ "$ELAPSED" -lt 0 ]; then
            ELAPSED=0
        fi

        ELAPSED_TEXT="$(
            progress_format_hms "$ELAPSED"
        )"

        if [ -e "$LOG_FILE" ]; then
            LOG_MTIME="$(
                stat -c %Y "$LOG_FILE" 2>/dev/null ||
                    printf '%s\n' "$NOW"
            )"

            LOG_AGE="$((NOW - LOG_MTIME))"

            if [ "$LOG_AGE" -lt 0 ]; then
                LOG_AGE=0
            fi

            LOG_TEXT="${LOG_AGE}s"
        else
            LOG_TEXT="-"
        fi

        COUNTS="$(
            progress_install_process_counts "$ROOT_PID"
        )"

        if [ -t 1 ] &&
           [ "${TERM:-dumb}" != "dumb" ]
        then
            printf '\r\033[2K  %s Install Wine runtime | %s | log %s | %s' \
                "${SPINNER[$FRAME]}" \
                "$ELAPSED_TEXT" \
                "$LOG_TEXT" \
                "$COUNTS"

            FRAME="$(((FRAME + 1) % ${#SPINNER[@]}))"
        else
            if [ "$NOW" -ge "$NEXT_TEXT_REPORT" ]; then
                printf \
                    'INSTALL_HEARTBEAT elapsed=%s log_age=%s %s\n' \
                    "$ELAPSED_TEXT" \
                    "$LOG_TEXT" \
                    "$COUNTS"

                NEXT_TEXT_REPORT="$((NOW + 30))"
            fi
        fi

        sleep 2
    done
}

progress_install_heartbeat_finish()
{
    if [ -t 1 ] &&
       [ "${TERM:-dumb}" != "dumb" ]
    then
        printf '\r\033[2K'
        printf '\n'
    fi
}

# === MU_INSTALLER_RUNTIME_INSTALL_HEARTBEAT_V1_END ===

# === MU_INSTALLER_PROGRESS_UI_V1_END ===

while [ "$#" -gt 0 ]
do
    case "$1" in
        --installer)
            [ "$#" -ge 2 ] || die "--installer requires a path"
            INSTALLER="$2"
            shift 2
            ;;

        --base)
            [ "$#" -ge 2 ] || die "--base requires a path"
            BASE="$2"
            shift 2
            ;;

        --skip-deps)
            SKIP_DEPS=1
            shift
            ;;

        --deps-only)
            DEPS_ONLY=1
            SKIP_DEPS=1
            shift
            ;;

        --configure-only)
            CONFIGURE_ONLY=1
            SKIP_DEPS=1
            shift
            ;;

        --build-only)
            BUILD_ONLY=1
            SKIP_DEPS=1
            shift
            ;;

        --runtime-only)
            RUNTIME_ONLY=1
            SKIP_DEPS=1
            shift
            ;;

        --prefix-only)
            PREFIX_ONLY=1
            SKIP_DEPS=1
            shift
            ;;

        --resume-from-prefix)
            RESUME_FROM_PREFIX=1
            SKIP_DEPS=1
            shift
            ;;

        --jobs)
            [ "$#" -ge 2 ] || die "--jobs requires a positive integer"
            BUILD_JOBS_OVERRIDE="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "unknown argument: $1"
            ;;
    esac
done

if [ "$DEPS_ONLY" -eq 1 ] && [ "$CONFIGURE_ONLY" -eq 1 ]; then
    die "--deps-only and --configure-only cannot be combined"
fi

if [ "$BUILD_ONLY" -eq 1 ] &&
   { [ "$DEPS_ONLY" -eq 1 ] || [ "$CONFIGURE_ONLY" -eq 1 ]; }; then
    die "--build-only cannot be combined with --deps-only or --configure-only"
fi

if [ "$RUNTIME_ONLY" -eq 1 ] &&
   { [ "$DEPS_ONLY" -eq 1 ] || [ "$CONFIGURE_ONLY" -eq 1 ] ||
     [ "$BUILD_ONLY" -eq 1 ]; }; then
    die "--runtime-only cannot be combined with other --*-only modes"
fi

if [ "$PREFIX_ONLY" -eq 1 ] &&
   { [ "$DEPS_ONLY" -eq 1 ] || [ "$CONFIGURE_ONLY" -eq 1 ] ||
     [ "$BUILD_ONLY" -eq 1 ] || [ "$RUNTIME_ONLY" -eq 1 ]; }; then
    die "--prefix-only cannot be combined with other --*-only modes"
fi

if [ "$RESUME_FROM_PREFIX" -eq 1 ] &&
   { [ "$DEPS_ONLY" -eq 1 ] || [ "$CONFIGURE_ONLY" -eq 1 ] ||
     [ "$BUILD_ONLY" -eq 1 ] || [ "$RUNTIME_ONLY" -eq 1 ] ||
     [ "$PREFIX_ONLY" -eq 1 ]; }; then
    die "--resume-from-prefix cannot be combined with other --*-only modes"
fi

if { [ "$PREFIX_ONLY" -eq 1 ] || [ "$RESUME_FROM_PREFIX" -eq 1 ]; } &&
   [ -n "$BUILD_JOBS_OVERRIDE" ]; then
    die "--jobs is not supported for --prefix-only or --resume-from-prefix"
fi

if [ -n "$BUILD_JOBS_OVERRIDE" ]; then
    case "$BUILD_JOBS_OVERRIDE" in
        *[!0-9]*|'') die "--jobs requires a positive integer" ;;
    esac
    [ "$BUILD_JOBS_OVERRIDE" -ge 1 ] 2>/dev/null ||
        die "--jobs requires a positive integer"
fi

if [ "$DEPS_ONLY" -eq 0 ] &&
   [ "$CONFIGURE_ONLY" -eq 0 ] &&
   [ "$BUILD_ONLY" -eq 0 ] &&
   [ "$RUNTIME_ONLY" -eq 0 ] &&
   [ "$PREFIX_ONLY" -eq 0 ]; then
    [ -n "$INSTALLER" ] || {
        usage
        die "official MU installer path is required"
    }

    INSTALLER="$(
        readlink -f -- "$INSTALLER"
    )" || die "cannot resolve installer path"

    [ -f "$INSTALLER" ] ||
        die "installer does not exist: $INSTALLER"
else
    INSTALLER="(not required for preliminary validation)"
fi

SOURCE_CACHE="$BASE/cache"
WORK="$BASE/work"

ARCHIVE="$SOURCE_CACHE/$WINE_ARCHIVE_NAME"
SOURCE="$WORK/wine-${WINE_VERSION}-patched"
BUILD="$WORK/build-wow64"
RUNTIME="$BASE/runtime/wine-${WINE_VERSION}-mu"

PREFIX="$BASE/prefix"

MU_DIR="$PREFIX/drive_c/Program Files (x86)/Webzen/Mu"

LOG_DIR="$BASE/logs"
BIN_DIR="$BASE/bin"

PINNED_PATH="$RUNTIME/bin:/usr/local/bin:/usr/bin:/bin"

GG_SERVICE='HKLM\System\CurrentControlSet\Services\GGKernel64'

GG_IMAGE_PATH='\??\C:\Program Files (x86)\Webzen\Mu\GameGuard\GGKernel64.sys'

if [ "$PREFIX_ONLY" -eq 1 ] || [ "$RESUME_FROM_PREFIX" -eq 1 ]; then
    if [ "$RESUME_FROM_PREFIX" -eq 1 ]; then
        log "Resume from validated private Wine runtime and pristine prefix"
    else
        log "Reuse existing private Wine runtime for pristine prefix"
    fi

    [ "$(uname -s)" = Linux ] || die "Linux required"
    [ "$(uname -m)" = x86_64 ] || die "x86_64 required"

    # shellcheck source=lib/platform-detect.sh
    . "$SCRIPT_DIR/lib/platform-detect.sh"
    # shellcheck source=lib/consent.sh
    . "$SCRIPT_DIR/lib/consent.sh"
    mu_detect_platform || die "platform detection failed"
    mu_platform_report

    if [ "$MU_DISTRO_STATUS" != verified ]; then
        [ -t 0 ] && [ -t 1 ] ||
            die "unverified distribution requires interactive confirmation"
        if [ "$RESUME_FROM_PREFIX" -eq 1 ]; then
            printf 'WARNING: this command runs the supplied MU installer and completes setup.\n'
            read -r -p 'Type CONTINUE to install MU on this unverified distro: ' CONSENT ||
                die "confirmation not received"
        else
            read -r -p 'Type CONTINUE to initialize a prefix on this unverified distro: ' CONSENT ||
                die "confirmation not received"
        fi
        mu_consent_matches "$CONSENT" CONTINUE ||
            die "experimental prefix initialization not approved"
    fi

    if [ "$PREFIX_ONLY" -eq 1 ]; then
        [ ! -e "$PREFIX" ] ||
            die "prefix already exists; --prefix-only must never overwrite it: $PREFIX"
    else
        [ -d "$PREFIX" ] ||
            die "existing prefix missing; --resume-from-prefix cannot initialize it"
        for REG in system.reg user.reg userdef.reg; do
            [ -f "$PREFIX/$REG" ] ||
                die "existing prefix registry file missing: $REG"
        done

        [ -f "$PREFIX/drive_c/windows/system32/notepad.exe" ] ||
            die "existing prefix has no x86_64 system32 notepad.exe"
        [ -f "$PREFIX/drive_c/windows/syswow64/notepad.exe" ] ||
            die "existing prefix has no i386 syswow64 notepad.exe"

        SYSTEM32_DESC="$(file -b "$PREFIX/drive_c/windows/system32/notepad.exe")"
        SYSWOW64_DESC="$(file -b "$PREFIX/drive_c/windows/syswow64/notepad.exe")"
        case "$SYSTEM32_DESC" in
            *PE32+*x86-64*) ;;
            *) die "existing prefix system32 architecture mismatch" ;;
        esac
        case "$SYSWOW64_DESC" in
            *PE32*Intel*i386*) ;;
            *) die "existing prefix syswow64 architecture mismatch" ;;
        esac

        [ ! -e "$MU_DIR" ] ||
            die "MU is already present; refusing to repeat official installation"
        if grep -Fiq 'GGKernel64' "$PREFIX/system.reg"; then
            die "existing prefix is not pristine: GGKernel64 registry entry present"
        fi
        GG_FOUND="$(find "$PREFIX/drive_c" -type f -iname GGKernel64.sys -print -quit)"
        [ -z "$GG_FOUND" ] ||
            die "existing prefix is not pristine: GameGuard driver present"
        printf 'V020_EXISTING_PREFIX_PRISTINE=True\n'
    fi

    [ -d "$BUILD" ] && [ -f "$BUILD/Makefile" ] &&
        [ -f "$BUILD/config.status" ] ||
        die "previously configured Wine build missing: $BUILD"

    [ -x "$RUNTIME/bin/wine" ] &&
        [ -x "$RUNTIME/bin/wineboot" ] &&
        [ -x "$RUNTIME/bin/wineserver" ] ||
        die "previously installed private Wine runtime is incomplete"

    [ "$("$RUNTIME/bin/wine" --version)" = "wine-$WINE_VERSION" ] ||
        die "private Wine version mismatch"

    # Recheck pinned patch files without modifying the patched source.
    [ -d "$REPO_ROOT/patches" ] || die "patch directory missing"
    for I in "${!PATCH_NAMES[@]}"; do
        PATCH="$REPO_ROOT/patches/${PATCH_NAMES[$I]}"
        [ -f "$PATCH" ] || die "missing pinned patch: $PATCH"
        ACTUAL="$(sha256sum "$PATCH" | awk '{print $1}')"
        [ "$ACTUAL" = "${PATCH_SHA256[$I]}" ] ||
            die "pinned patch checksum mismatch: $PATCH"
    done

    log "Verify installed Wine artifacts are identical to build outputs"
    PAIRS=(
        "dlls/ntdll/ntdll.so|lib/wine/x86_64-unix/ntdll.so"
        "dlls/ntdll/i386-windows/ntdll.dll|lib/wine/i386-windows/ntdll.dll"
        "dlls/ntdll/x86_64-windows/ntdll.dll|lib/wine/x86_64-windows/ntdll.dll"
        "dlls/kernelbase/i386-windows/kernelbase.dll|lib/wine/i386-windows/kernelbase.dll"
        "dlls/kernelbase/x86_64-windows/kernelbase.dll|lib/wine/x86_64-windows/kernelbase.dll"
        "dlls/ntoskrnl.exe/i386-windows/ntoskrnl.exe|lib/wine/i386-windows/ntoskrnl.exe"
        "dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe|lib/wine/x86_64-windows/ntoskrnl.exe"
        "dlls/winepulse.drv/winepulse.so|lib/wine/x86_64-unix/winepulse.so"
        "dlls/winealsa.drv/winealsa.so|lib/wine/x86_64-unix/winealsa.so"
    )
    for PAIR in "${PAIRS[@]}"; do
        BUILD_REL="${PAIR%%|*}"
        RUNTIME_REL="${PAIR#*|}"
        cmp -s -- "$BUILD/$BUILD_REL" "$RUNTIME/$RUNTIME_REL" ||
            die "runtime/build mismatch: $RUNTIME_REL"
        printf 'IDENTICAL %s\n' "$RUNTIME_REL"
    done
    printf 'V020_EXISTING_RUNTIME_VERIFIED=True\n'

    [ -d "$LOG_DIR" ] ||
        die "missing existing log directory: $LOG_DIR"

    progress_begin
    if [ "$RESUME_FROM_PREFIX" -eq 1 ]; then
        PROGRESS_DONE=6
    else
        PROGRESS_DONE=5
    fi
else
log "Platform preflight"

[ "$(uname -s)" = "Linux" ] ||
    die "this installer currently supports Linux only"

[ "$(uname -m)" = "x86_64" ] ||
    die "this installer currently supports x86_64 only"

[ -r /etc/os-release ] ||
    die "/etc/os-release not found"

# shellcheck disable=SC1091
. /etc/os-release

printf 'Distribution: %s\n' "${PRETTY_NAME:-unknown}"
printf 'Architecture: %s\n' "$(uname -m)"

# v0.2.0: independent platform, package manager and build validation.
# The legacy recipes for Fedora/Nobara and Ubuntu remain unchanged.
# shellcheck source=lib/platform-detect.sh
. "$SCRIPT_DIR/lib/platform-detect.sh"
mu_detect_platform || die "platform detection failed"
mu_platform_report
# shellcheck source=lib/consent.sh
. "$SCRIPT_DIR/lib/consent.sh"

case "${ID:-}" in
    fedora)
        DISTRO_FAMILY="fedora"
        DISTRO_VERSION="${VERSION_ID:-}"

        if [ "$DISTRO_VERSION" != "44" ]; then
            printf 'WARNING: verified Fedora reference is Fedora 44; detected Fedora %s\n' \
                "${DISTRO_VERSION:-unknown}"
        fi
        ;;

    nobara)
        DISTRO_FAMILY="fedora"
        DISTRO_VERSION="${VERSION_ID:-}"

        if [ "$DISTRO_VERSION" != "44" ]; then
            echo "WARNING: Nobara validation target is 44; detected Nobara ${DISTRO_VERSION:-unknown}"
        fi
        ;;

    ubuntu)
        DISTRO_FAMILY="ubuntu"
        DISTRO_VERSION="${VERSION_ID:-}"

        if [ "$DISTRO_VERSION" != "26.04" ]; then
            printf 'WARNING: current Ubuntu validation target is Ubuntu 26.04; detected Ubuntu %s\n' \
                "${DISTRO_VERSION:-unknown}"
        fi
        ;;

    cachyos)
        # CachyOS uses the E2E-tested native Pacman dependency recipe.
        DISTRO_FAMILY="portable"
        DISTRO_VERSION="${VERSION_ID:-}"
        [ "$MU_DISTRO_STATUS" = verified ] ||
            echo "WARNING: CachyOS environment differs from tested rolling-release reference."
        ;;

    *)
        # An unknown distro is not a fatal error by itself. The independent
        # build validator decides whether compilation prerequisites exist.
        DISTRO_FAMILY="portable"
        DISTRO_VERSION="${VERSION_ID:-}"
        echo "WARNING: unverified distribution; dependency setup will be selected separately."
        ;;
esac

# Explicit consent before any package or Wine operation on unverified OS.
# Read-only --deps-only deliberately needs no confirmation.
if [ "$DEPS_ONLY" -eq 0 ] &&
   [ "$MU_DISTRO_STATUS" != verified ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        die "unverified distribution requires interactive confirmation"
    fi
    printf '\nUnverified distribution: %s\n' "${PRETTY_NAME:-unknown}"
    printf '%s\n' "MU Online compatibility and GameGuard have not been validated here."
    read -r -p 'Type CONTINUE to proceed with experimental installation: ' CONSENT ||
        die "confirmation not received"
    mu_consent_matches "$CONSENT" CONTINUE || die "experimental installation not approved"
fi

log "Repository validation"

[ -d "$REPO_ROOT/patches" ] ||
    die "patches directory missing"

for I in "${!PATCH_NAMES[@]}"
do
    PATCH="$REPO_ROOT/patches/${PATCH_NAMES[$I]}"
    EXPECTED="${PATCH_SHA256[$I]}"

    [ -f "$PATCH" ] ||
        die "missing patch: $PATCH"

    ACTUAL="$(
        sha256sum "$PATCH" |
            awk '{print $1}'
    )"

    printf '%s  %s\n' "$ACTUAL" "${PATCH_NAMES[$I]}"

    [ "$ACTUAL" = "$EXPECTED" ] ||
        die "patch checksum mismatch: ${PATCH_NAMES[$I]}"
done

log "Required command preflight"

COMMANDS=(
    awk
    bison
    curl
    file
    flex
    gcc
    make
    patch
    python3
    pkg-config
    sha256sum
    tar
    x86_64-w64-mingw32-gcc
    cmp
    find
    grep
    perl
    readlink
    sed
    stat
)

MISSING_COMMANDS=()

for CMD in "${COMMANDS[@]}"
do
    if command -v "$CMD" >/dev/null 2>&1; then
        printf 'OK      %s\n' "$CMD"
    else
        printf 'MISSING %s\n' "$CMD"
        MISSING_COMMANDS+=("$CMD")
    fi
done

if [ "${#MISSING_COMMANDS[@]}" -gt 0 ] &&
   [ "$SKIP_DEPS" -eq 1 ] &&
   [ "$DEPS_ONLY" -eq 0 ]
then
    die "required build commands are missing and --skip-deps was requested"
fi

# --deps-only must reach the independent validator even when tools are
# absent; only the validator can provide the complete missing dependency list.

log "Configuration"

printf 'Repository:  %s\n' "$REPO_ROOT"
printf 'Installer:   %s\n' "$INSTALLER"
printf 'Base:        %s\n' "$BASE"
printf 'Wine source: %s\n' "$WINE_SOURCE_URL"
printf 'Runtime:     %s\n' "$RUNTIME"
printf 'Prefix:      %s\n' "$PREFIX"

printf '\nINSTALLER_STAGE_1_PREFLIGHT_PASS=True\n'

progress_begin

# === MU_INSTALLER_STAGE_2A_DISTRO_DEPS_BEGIN ===

progress_stage_start "System dependencies"

run_root()
{
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return
    fi

    command -v sudo >/dev/null 2>&1 ||
        die "sudo is required to install system dependencies"

    sudo "$@"
}

. "$SCRIPT_DIR/lib/native-deps.sh"

log "Build dependencies"

if [ "$SKIP_DEPS" -eq 0 ]; then
    case "$DISTRO_FAMILY" in
        fedora)
            command -v dnf >/dev/null 2>&1 ||
                die "dnf not found on Fedora system"

            printf 'Installing %s Fedora packages/dependency roots.\n' \
                "${#FEDORA_PACKAGES[@]}"

            if ! run_root \
                dnf install -y \
                "${FEDORA_PACKAGES[@]}"; then
                echo 'NOTICE: DNF could not install all dependency roots.'
                bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive ||
                    die "manual dependency preparation did not complete"
            fi
            ;;

        ubuntu)
            command -v apt-get >/dev/null 2>&1 ||
                die "apt-get not found on Ubuntu system"

            command -v dpkg >/dev/null 2>&1 ||
                die "dpkg not found on Ubuntu system"

            [ "$(dpkg --print-architecture)" = "amd64" ] ||
                die "Ubuntu backend currently requires amd64"

            I386_ENABLED=0

            while IFS= read -r ARCH; do
                if [ "$ARCH" = "i386" ]; then
                    I386_ENABLED=1
                    break
                fi
            done < <(dpkg --print-foreign-architectures)

            if [ "$I386_ENABLED" -eq 0 ]; then
                log "Enable Ubuntu i386 architecture"
                run_root dpkg --add-architecture i386
            else
                printf 'Ubuntu i386 architecture already enabled.\n'
            fi

            log "Refresh Ubuntu package metadata"

            APT_PREPARED=1
            if ! run_root \
                env DEBIAN_FRONTEND=noninteractive \
                apt-get update; then
                APT_PREPARED=0
            fi

            printf 'Installing %s Ubuntu packages/dependency roots.\n' \
                "${#UBUNTU_PACKAGES[@]}"

            if [ "$APT_PREPARED" -eq 1 ] &&
               ! run_root \
                env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y \
                "${UBUNTU_PACKAGES[@]}"; then
                APT_PREPARED=0
            fi
            if [ "$APT_PREPARED" -ne 1 ]; then
                echo 'NOTICE: APT could not install all dependency roots.'
                bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive ||
                    die "manual dependency preparation did not complete"
            fi
            ;;

        portable)
            # Unverified systems already approved CONTINUE above. Prefer
            # the discovered *native* package manager, but never mark an
            # experimental distribution as verified. Unknown managers,
            # unavailable packages and failed build checks use the manual
            # audit/retry loop instead of stopping at the package-name error.
            EXPERIMENTAL_READY=0
            case "$MU_PKG_BACKEND" in
                pacman)
                    echo 'Experimental Pacman dependency preparation.'
                    if bash "$SCRIPT_DIR/pacman-deps-prepare.sh" --install; then
                        EXPERIMENTAL_READY=1
                    fi
                    ;;
                dnf|apt)
                    echo "Experimental native $MU_PKG_BACKEND dependency preparation."
                    if bash "$SCRIPT_DIR/native-deps-prepare.sh" "$MU_PKG_BACKEND" --install; then
                        EXPERIMENTAL_READY=1
                    fi
                    ;;
                *)
                    echo 'NOTICE: native package manager unknown; manual dependency preparation required.'
                    ;;
            esac

            if [ "$EXPERIMENTAL_READY" -eq 1 ]; then
                # A completed package transaction is not proof that Wine
                # has all 32/64-bit compiler, link and library prerequisites.
                if ! bash "$SCRIPT_DIR/build-env-audit.sh"; then
                    EXPERIMENTAL_READY=0
                fi
            fi
            if [ "$EXPERIMENTAL_READY" -ne 1 ]; then
                echo 'NOTICE: automatic dependency preparation was unavailable or incomplete.'
                echo 'Install missing requirements manually, then recheck.'
                bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive ||
                    die "manual dependency preparation did not complete"
            fi
            ;;

        *)
            die "internal error: unknown dependency backend"
            ;;
    esac
else
    printf 'Dependency installation skipped by --skip-deps.\n'
fi

# Normal installs may still lack optional toolchain/library prerequisites
# after a seemingly successful native transaction. Offer the same manual
# recheck path; --skip-deps and --deps-only stay read-only/noninteractive.
if [ "$SKIP_DEPS" -eq 0 ] && [ "$DEPS_ONLY" -eq 0 ]; then
    if ! bash "$SCRIPT_DIR/build-env-audit.sh"; then
        echo 'NOTICE: build prerequisites are incomplete after package preparation.'
        bash "$SCRIPT_DIR/manual-deps-prepare.sh" --interactive ||
            die "manual dependency preparation did not complete"
    fi
fi

log "Build tool validation"

REQUIRED_COMMANDS=(
    awk
    bison
    curl
    file
    flex
    g++
    gcc
    make
    msgfmt
    patch
    python3
    pkg-config
    sha256sum
    tar
    xz

    i686-w64-mingw32-gcc
    i686-w64-mingw32-ld
    x86_64-w64-mingw32-gcc
    x86_64-w64-mingw32-ld
    cmp
    find
    grep
    perl
    readlink
    sed
    stat
)

for CMD in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$CMD" >/dev/null 2>&1 ||
        die "required command missing after dependency stage: $CMD"
    printf 'OK      %s\n' "$CMD"
done

log "Native development library validation"

REQUIRED_PKGCONFIG=(
    freetype2
    gnutls
    x11
    xcursor
    xi
    xrandr
    wayland-client
    egl
    gbm
    vulkan
    libpulse
    alsa
)

for PC in "${REQUIRED_PKGCONFIG[@]}"; do
    if pkg-config --exists "$PC"; then
        printf 'OK      pkg-config %s\n' "$PC"
    else
        die "required pkg-config module missing: $PC"
    fi
done

log "PulseAudio / ALSA multilib validation"

case "$DISTRO_FAMILY" in
    fedora)
        AUDIO_PC_FILES=(
            /usr/lib64/pkgconfig/libpulse.pc
            /usr/lib/pkgconfig/libpulse.pc
            /usr/lib64/pkgconfig/alsa.pc
            /usr/lib/pkgconfig/alsa.pc
        )
        ;;

    ubuntu)
        AUDIO_PC_FILES=(
            /usr/lib/x86_64-linux-gnu/pkgconfig/libpulse.pc
            /usr/lib/i386-linux-gnu/pkgconfig/libpulse.pc
            /usr/lib/x86_64-linux-gnu/pkgconfig/alsa.pc
            /usr/lib/i386-linux-gnu/pkgconfig/alsa.pc
        )
        ;;

    portable)
        # No hardcoded library paths for unverified distributions.
        # The common validator below compiles and links the 32-bit ABI.
        AUDIO_PC_FILES=()
        ;;
esac

for PC_FILE in "${AUDIO_PC_FILES[@]}"; do
    [ -f "$PC_FILE" ] ||
        die "required audio development file missing: $PC_FILE"
    printf 'OK      %s\n' "$PC_FILE"
done

# Mandatory for --skip-deps too: skip installation, never skip validation.
log "Independent build/link/ABI validation"
bash "$SCRIPT_DIR/build-env-audit.sh" ||
    die "independent build environment audit failed"
printf 'V020_BUILD_ENV_AUDIT_PASS=True\n'

printf '\nINSTALLER_STAGE_2A_DISTRO_DEPS_PASS=True\n'

case "$DISTRO_FAMILY" in
    fedora)
        printf 'INSTALLER_STAGE_2A_FEDORA_DEPS_PASS=True\n'
        ;;

    ubuntu)
        printf 'INSTALLER_STAGE_2A_UBUNTU_DEPS_PASS=True\n'
        ;;
esac

progress_stage_complete "System dependencies"

if [ "$DEPS_ONLY" -eq 1 ]; then
    printf '\nV020_INSTALLER_DEPENDENCIES_ONLY_PASS=True\n'
    echo 'No Wine download, compilation, prefix or game installation was started.'
    exit 0
fi

# === MU_INSTALLER_STAGE_2A_DISTRO_DEPS_END ===

# === MU_INSTALLER_STAGE_2B_SOURCE_PATCH_BEGIN ===

progress_stage_start "Wine source and patches"

verify_sha256()
{
    FILE_PATH="$1"
    EXPECTED_SHA="$2"

    ACTUAL_SHA="$(
        sha256sum "$FILE_PATH" |
            awk '{print $1}'
    )"

    printf 'SHA256 %s  %s\n' \
        "$ACTUAL_SHA" \
        "$FILE_PATH"

    [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]
}

log "Prepare installation workspace"

mkdir -p \
    "$SOURCE_CACHE" \
    "$WORK" \
    "$LOG_DIR" \
    "$BIN_DIR" \
    "$BASE/runtime"

log "Acquire pristine Wine ${WINE_VERSION} source"

if [ -f "$ARCHIVE" ]; then
    if verify_sha256 \
        "$ARCHIVE" \
        "$WINE_ARCHIVE_SHA256"
    then
        printf 'Using verified cached archive: %s\n' "$ARCHIVE"
    else
        BAD_ARCHIVE="$ARCHIVE.bad.$(date +%Y%m%d_%H%M%S)"

        printf 'Cached archive checksum mismatch.\n'
        printf 'Preserving bad archive as: %s\n' "$BAD_ARCHIVE"

        mv -- \
            "$ARCHIVE" \
            "$BAD_ARCHIVE"
    fi
fi

if [ ! -f "$ARCHIVE" ]; then
    DOWNLOAD_TMP="$ARCHIVE.part.$$"

    rm -f -- "$DOWNLOAD_TMP"

    printf 'Downloading: %s\n' "$WINE_SOURCE_URL"

    if ! curl \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --output "$DOWNLOAD_TMP" \
        "$WINE_SOURCE_URL"
    then
        rm -f -- "$DOWNLOAD_TMP"
        die "Wine source download failed"
    fi

    if ! verify_sha256 \
        "$DOWNLOAD_TMP" \
        "$WINE_ARCHIVE_SHA256"
    then
        BAD_DOWNLOAD="$ARCHIVE.bad-sha.$(date +%Y%m%d_%H%M%S)"

        mv -- \
            "$DOWNLOAD_TMP" \
            "$BAD_DOWNLOAD"

        die "downloaded Wine archive checksum mismatch; preserved as $BAD_DOWNLOAD"
    fi

    mv -- \
        "$DOWNLOAD_TMP" \
        "$ARCHIVE"

    printf 'Verified archive stored as: %s\n' "$ARCHIVE"
fi

verify_sha256 \
    "$ARCHIVE" \
    "$WINE_ARCHIVE_SHA256" ||
    die "Wine archive checksum validation failed"

log "Validate Wine archive layout"

ARCHIVE_CONFIGURE_COUNT="$(
    tar -tf "$ARCHIVE" |
        awk -v target="wine-${WINE_VERSION}/configure" '
            $0 == target { count++ }
            END { print count + 0 }
        '
)"

printf 'ARCHIVE_CONFIGURE_COUNT=%s\n' \
    "$ARCHIVE_CONFIGURE_COUNT"

[ "$ARCHIVE_CONFIGURE_COUNT" -eq 1 ] ||
    die "unexpected Wine archive layout"

log "Prepare Wine source tree"

if [ ! -d "$SOURCE" ]; then
    EXTRACT_TMP="$WORK/.wine-${WINE_VERSION}-extract.$$"

    [ ! -e "$EXTRACT_TMP" ] ||
        die "temporary extraction path already exists: $EXTRACT_TMP"

    mkdir -p "$EXTRACT_TMP"

    tar -xf \
        "$ARCHIVE" \
        -C "$EXTRACT_TMP"

    EXTRACTED_SOURCE="$EXTRACT_TMP/wine-${WINE_VERSION}"

    [ -d "$EXTRACTED_SOURCE" ] ||
        die "Wine source directory missing after extraction"

    [ -x "$EXTRACTED_SOURCE/configure" ] ||
        die "Wine configure script missing after extraction"

    mv -- \
        "$EXTRACTED_SOURCE" \
        "$SOURCE"

    rmdir "$EXTRACT_TMP"

    printf 'Pristine source extracted: %s\n' "$SOURCE"
else
    printf 'Existing source workspace found: %s\n' "$SOURCE"
    printf 'Patch state will be validated before reuse.\n'
fi

[ -x "$SOURCE/configure" ] ||
    die "Wine source configure script missing"

log "Apply repository patch sequence"

for I in "${!PATCH_NAMES[@]}"
do
    PATCH_NAME="${PATCH_NAMES[$I]}"
    PATCH_FILE="$REPO_ROOT/patches/$PATCH_NAME"

    printf '\nPatch %s\n' "$PATCH_NAME"

    if (
        cd "$SOURCE"

        patch \
            --dry-run \
            --forward \
            --batch \
            -p1 \
            < "$PATCH_FILE" \
            >/dev/null
    )
    then
        printf 'State: applicable\n'

        (
            cd "$SOURCE"

            patch \
                --forward \
                --batch \
                -p1 \
                < "$PATCH_FILE"
        )

        printf 'Applied: %s\n' "$PATCH_NAME"

    elif (
        cd "$SOURCE"

        patch \
            --dry-run \
            --reverse \
            --batch \
            -p1 \
            < "$PATCH_FILE" \
            >/dev/null
    )
    then
        printf 'State: already applied\n'

    else
        die "source tree is not compatible with patch: $PATCH_NAME"
    fi
done

log "Verify complete patch sequence"

for I in "${!PATCH_NAMES[@]}"
do
    PATCH_NAME="${PATCH_NAMES[$I]}"
    PATCH_FILE="$REPO_ROOT/patches/$PATCH_NAME"

    if (
        cd "$SOURCE"

        patch \
            --dry-run \
            --reverse \
            --batch \
            -p1 \
            < "$PATCH_FILE" \
            >/dev/null
    )
    then
        printf 'VERIFIED APPLIED  %s\n' "$PATCH_NAME"
    else
        die "final patch verification failed: $PATCH_NAME"
    fi
done

log "Patched source structural validation"

REQUIRED_SOURCE_FILES=(
    dlls/kernelbase/path.c
    dlls/ntdll/Makefile.in
    dlls/ntdll/driver.c
    dlls/ntdll/ntsyscalls.h
    dlls/ntdll/signal_i386.c
    dlls/ntdll/signal_x86_64.c
    dlls/ntdll/unix/thread.c
    dlls/ntdll/unix/unix_private.h
    dlls/ntdll/unix/virtual.c
    dlls/ntoskrnl.exe/ntoskrnl.c
    dlls/ntoskrnl.exe/ntoskrnl.exe.spec
    tools/make_specfiles
)

for REL in "${REQUIRED_SOURCE_FILES[@]}"
do
    [ -f "$SOURCE/$REL" ] ||
        die "required patched source file missing: $REL"

    printf 'PRESENT %s\n' "$REL"
done

[ -f "$SOURCE/dlls/ntdll/driver.c" ] ||
    die "NtLoadDriver SCM implementation source missing"

grep -F \
    'NtLoadDriver' \
    "$SOURCE/dlls/ntdll/driver.c" \
    >/dev/null ||
    die "NtLoadDriver implementation marker missing"

grep -F \
    'KeGetCurrentIrql' \
    "$SOURCE/dlls/ntoskrnl.exe/ntoskrnl.c" \
    >/dev/null ||
    die "ntoskrnl compatibility marker missing"

printf '\nINSTALLER_STAGE_2B_SOURCE_PATCH_PASS=True\n'

progress_stage_complete "Wine source and patches"

# === MU_INSTALLER_STAGE_2B_SOURCE_PATCH_END ===

# === MU_INSTALLER_STAGE_2C_CONFIGURE_BEGIN ===

progress_stage_start "Configure Wine 11.6"

CONFIGURE_LOG="$LOG_DIR/wine-${WINE_VERSION}-configure.log"

make_variable()
{
    VARIABLE_NAME="$1"
    MAKEFILE_PATH="$2"

    python3 - \
        "$VARIABLE_NAME" \
        "$MAKEFILE_PATH" <<'PY'
from pathlib import Path
import re
import sys

name = sys.argv[1]
path = Path(sys.argv[2])

lines = path.read_text(
    errors="replace"
).splitlines()

pattern = re.compile(
    r"^" + re.escape(name) + r"[ \t]*=[ \t]*(.*)$"
)

for index, line in enumerate(lines):
    match = pattern.match(line)

    if not match:
        continue

    parts = []
    value = match.group(1)

    while True:
        continued = value.rstrip().endswith("\\")

        if continued:
            value = value.rstrip()[:-1]

        value = value.strip()

        if value:
            parts.append(value)

        if not continued:
            break

        index += 1

        if index >= len(lines):
            raise SystemExit(
                f"unterminated Makefile variable: {name}"
            )

        value = lines[index]

    print(" ".join(parts))
    raise SystemExit(0)

raise SystemExit(
    f"Makefile variable not found: {name}"
)
PY
}

log "Configure Wine ${WINE_VERSION} WoW64"

[ -x "$SOURCE/configure" ] ||
    die "Wine configure script missing"

if [ -e "$RUNTIME" ]; then
    die "runtime path already exists before build: $RUNTIME"
fi

if [ ! -e "$BUILD" ]; then
    mkdir -p "$BUILD"

    printf 'Fresh build directory: %s\n' "$BUILD"

    (
        cd "$BUILD"

        "$SOURCE/configure" \
            --prefix="$RUNTIME" \
            --enable-archs=i386,x86_64
    ) 2>&1 |
        tee "$CONFIGURE_LOG"

elif [ -f "$BUILD/Makefile" ] &&
     [ -f "$BUILD/config.status" ]
then
    printf 'Existing configured build directory found: %s\n' \
        "$BUILD"

    printf 'Existing configuration will be validated and reused.\n'

else
    die "build directory exists but is not a complete configured build: $BUILD"
fi

[ -f "$BUILD/Makefile" ] ||
    die "configure did not produce Makefile"

[ -f "$BUILD/config.status" ] ||
    die "configure did not produce config.status"

log "Validate configure arguments"

grep -Fq \
    -- "--prefix=$RUNTIME --enable-archs=i386,x86_64" \
    "$BUILD/config.status" ||
    die "configure arguments do not match verified MU build"

printf 'CONFIGURE_ARGUMENTS_OK=True\n'

log "Validate WoW64 PE architectures"

PE_ARCHS="$(
    make_variable \
        PE_ARCHS \
        "$BUILD/Makefile"
)"

printf 'PE_ARCHS=%s\n' "$PE_ARCHS"

[ "$PE_ARCHS" = "i386 x86_64" ] ||
    die "unexpected PE_ARCHS: $PE_ARCHS"

printf 'WOW64_ARCHS_OK=True\n'

log "Validate Wine audio configuration"

PULSE_CFLAGS="$(
    make_variable \
        PULSE_CFLAGS \
        "$BUILD/Makefile"
)"

PULSE_LIBS="$(
    make_variable \
        PULSE_LIBS \
        "$BUILD/Makefile"
)"

ALSA_LIBS="$(
    make_variable \
        ALSA_LIBS \
        "$BUILD/Makefile"
)"

printf 'PULSE_CFLAGS=%s\n' "$PULSE_CFLAGS"
printf 'PULSE_LIBS=%s\n' "$PULSE_LIBS"
printf 'ALSA_LIBS=%s\n' "$ALSA_LIBS"

[ -n "$PULSE_LIBS" ] ||
    die "PulseAudio was not enabled by Wine configure"

[ -n "$ALSA_LIBS" ] ||
    die "ALSA was not enabled by Wine configure"

printf 'PULSE_LIBS_PRESENT=True\n'
printf 'ALSA_LIBS_PRESENT=True\n'

log "Validate audio driver enablement"

DISABLED_SUBDIRS="$(
    make_variable \
        DISABLED_SUBDIRS \
        "$BUILD/Makefile"
)"

case " $DISABLED_SUBDIRS " in
    *" dlls/winepulse.drv "*|*" winepulse.drv "*)
        die "winepulse.drv is disabled"
        ;;
esac

case " $DISABLED_SUBDIRS " in
    *" dlls/winealsa.drv "*|*" winealsa.drv "*)
        die "winealsa.drv is disabled"
        ;;
esac

printf 'WINEPULSE_DISABLED=False\n'
printf 'WINEALSA_DISABLED=False\n'
printf 'AUDIO_DRIVERS_ENABLED=True\n'

# === MU_INSTALLER_GNUTLS_SCHANNEL_VALIDATE_V1 ===
log "Validate GnuTLS / Schannel enablement"

grep -F \
    'checking for gnutls/gnutls.h... yes' \
    "$CONFIGURE_LOG" \
    >/dev/null ||
    die "GnuTLS development headers were not detected by Wine configure"

grep -F \
    'checking for gnutls_cipher_init... yes' \
    "$CONFIGURE_LOG" \
    >/dev/null ||
    die "Wine configure did not validate GnuTLS cipher support"

if grep -Fi \
    'no schannel support' \
    "$CONFIGURE_LOG" \
    >/dev/null
then
    die "Wine configure disabled Schannel support"
fi

printf 'GNUTLS_HEADER_DETECTED=True\n'
printf 'GNUTLS_CIPHER_DETECTED=True\n'
printf 'SCHANNEL_ENABLED=True\n'

log "Validate patched source survived configure"

grep -F \
    'NtLoadDriver' \
    "$SOURCE/dlls/ntdll/driver.c" \
    >/dev/null ||
    die "NtLoadDriver source marker disappeared"

grep -F \
    'KeGetCurrentIrql' \
    "$SOURCE/dlls/ntoskrnl.exe/ntoskrnl.c" \
    >/dev/null ||
    die "ntoskrnl compatibility source marker disappeared"

printf 'PATCHED_SOURCE_STILL_PRESENT=True\n'

log "Runtime state before compilation"

if [ -e "$RUNTIME" ]; then
    die "configure unexpectedly created runtime path"
fi

printf 'RUNTIME_CREATED_DURING_CONFIGURE=False\n'

printf '\nINSTALLER_STAGE_2C_CONFIGURE_PASS=True\n'

progress_stage_complete "Configure Wine 11.6"

if [ "$CONFIGURE_ONLY" -eq 1 ]; then
    printf '\nV020_WINE_CONFIGURE_ONLY_PASS=True\n'
    printf 'SOURCE_REUSABLE=%s\n' "$SOURCE"
    printf 'BUILD_REUSABLE=%s\n' "$BUILD"
    echo 'Wine was configured, but no compilation, runtime installation,'
    echo 'Wine prefix creation or MU Online installation was started.'
    exit 0
fi

# === MU_INSTALLER_STAGE_2C_CONFIGURE_END ===

# === MU_INSTALLER_STAGE_2D_BUILD_BEGIN ===

progress_stage_start "Build Wine 11.6"

BUILD_LOG="$LOG_DIR/wine-${WINE_VERSION}-build.log"

log "Build Wine ${WINE_VERSION} WoW64"

[ -d "$BUILD" ] ||
    die "Wine build directory missing"

[ -f "$BUILD/Makefile" ] ||
    die "Wine build Makefile missing"

[ ! -e "$RUNTIME" ] ||
    die "runtime already exists before compilation: $RUNTIME"

if [ -n "$BUILD_JOBS_OVERRIDE" ]; then
    JOBS="$BUILD_JOBS_OVERRIDE"
else
    JOBS="$(
        nproc 2>/dev/null ||
            printf '1\n'
    )"
fi

case "$JOBS" in
    ''|*[!0-9]*)
        die "invalid build job count: $JOBS"
        ;;
esac

[ "$JOBS" -ge 1 ] ||
    die "invalid build job count: $JOBS"

printf 'BUILD=%s\n' "$BUILD"
printf 'JOBS=%s\n' "$JOBS"
printf 'BUILD_LOG=%s\n' "$BUILD_LOG"

START_EPOCH="$(date +%s)"

progress_build_heartbeat \
    "$$" \
    "$START_EPOCH" \
    "$BUILD_LOG" &

BUILD_HEARTBEAT_PID=$!

printf 'BUILD_HEARTBEAT_PID=%s\n' \
    "$BUILD_HEARTBEAT_PID"

set +e

make \
    -C "$BUILD" \
    -j"$JOBS" \
    >"$BUILD_LOG" 2>&1

MAKE_RC=$?

set -e

if kill -0 "$BUILD_HEARTBEAT_PID" 2>/dev/null; then
    kill "$BUILD_HEARTBEAT_PID" 2>/dev/null ||
        true
fi

wait "$BUILD_HEARTBEAT_PID" 2>/dev/null ||
    true

progress_build_heartbeat_finish

END_EPOCH="$(date +%s)"
BUILD_SECONDS="$((END_EPOCH - START_EPOCH))"

printf 'MAKE_RC=%s\n' "$MAKE_RC"
printf 'BUILD_SECONDS=%s\n' "$BUILD_SECONDS"

if [ "$MAKE_RC" -ne 0 ]; then
    printf '\n--- BUILD LOG TAIL ---\n'

    tail -n 120 \
        "$BUILD_LOG" \
        || true

    printf '\n--- ERROR-LIKE BUILD LINES ---\n'

    grep -niE \
        '(^|[^a-z])(error:|fatal error:|undefined reference|collect2: error|make(\[[0-9]+\])?: \*\*\*)' \
        "$BUILD_LOG" \
        | sed -n '1,100p' \
        || true

    die "Wine build failed with rc=$MAKE_RC"
fi

printf 'WINE_BUILD_COMPLETED=True\n'

log "Validate required build outputs"

REQUIRED_BUILD_OUTPUTS=(
    dlls/ntdll/ntdll.so
    dlls/ntdll/i386-windows/ntdll.dll
    dlls/ntdll/x86_64-windows/ntdll.dll

    dlls/kernelbase/i386-windows/kernelbase.dll
    dlls/kernelbase/x86_64-windows/kernelbase.dll

    dlls/ntoskrnl.exe/i386-windows/ntoskrnl.exe
    dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe

    dlls/winepulse.drv/winepulse.so
    dlls/winealsa.drv/winealsa.so
)

for REL in "${REQUIRED_BUILD_OUTPUTS[@]}"
do
    [ -f "$BUILD/$REL" ] ||
        die "required build output missing: $REL"

    printf 'PRESENT %s\n' "$REL"
done

printf 'REQUIRED_BUILD_OUTPUTS_PRESENT=True\n'

log "Validate output architectures"

I386_NTDLL_DESC="$(
    file -b \
        "$BUILD/dlls/ntdll/i386-windows/ntdll.dll"
)"

X64_NTDLL_DESC="$(
    file -b \
        "$BUILD/dlls/ntdll/x86_64-windows/ntdll.dll"
)"

X64_NTOS_DESC="$(
    file -b \
        "$BUILD/dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe"
)"

PULSE_DESC="$(
    file -b \
        "$BUILD/dlls/winepulse.drv/winepulse.so"
)"

ALSA_DESC="$(
    file -b \
        "$BUILD/dlls/winealsa.drv/winealsa.so"
)"

printf 'I386_NTDLL=%s\n' "$I386_NTDLL_DESC"
printf 'X64_NTDLL=%s\n' "$X64_NTDLL_DESC"
printf 'X64_NTOSKRNL=%s\n' "$X64_NTOS_DESC"
printf 'WINEPULSE=%s\n' "$PULSE_DESC"
printf 'WINEALSA=%s\n' "$ALSA_DESC"

case "$I386_NTDLL_DESC" in
    *PE32*Intel*i386*)
        ;;
    *)
        die "i386 ntdll has unexpected architecture"
        ;;
esac

case "$X64_NTDLL_DESC" in
    *PE32+*x86-64*)
        ;;
    *)
        die "x86_64 ntdll has unexpected architecture"
        ;;
esac

case "$X64_NTOS_DESC" in
    *PE32+*x86-64*)
        ;;
    *)
        die "x86_64 ntoskrnl has unexpected architecture"
        ;;
esac

case "$PULSE_DESC" in
    *ELF*64-bit*x86-64*)
        ;;
    *)
        die "winepulse.so has unexpected architecture"
        ;;
esac

case "$ALSA_DESC" in
    *ELF*64-bit*x86-64*)
        ;;
    *)
        die "winealsa.so has unexpected architecture"
        ;;
esac

printf 'BUILD_ARCHITECTURES_OK=True\n'

log "Record build artifact hashes"

sha256sum \
    "$BUILD/dlls/ntdll/ntdll.so" \
    "$BUILD/dlls/ntdll/i386-windows/ntdll.dll" \
    "$BUILD/dlls/ntdll/x86_64-windows/ntdll.dll" \
    "$BUILD/dlls/kernelbase/i386-windows/kernelbase.dll" \
    "$BUILD/dlls/kernelbase/x86_64-windows/kernelbase.dll" \
    "$BUILD/dlls/ntoskrnl.exe/i386-windows/ntoskrnl.exe" \
    "$BUILD/dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe" \
    "$BUILD/dlls/winepulse.drv/winepulse.so" \
    "$BUILD/dlls/winealsa.drv/winealsa.so"

log "Verify runtime and prefix remain untouched"

[ ! -e "$RUNTIME" ] ||
    die "runtime unexpectedly exists before make install"

[ ! -e "$PREFIX" ] ||
    die "Wine prefix unexpectedly exists during build stage"

printf 'MAKE_INSTALL_EXECUTED=False\n'
printf 'RUNTIME_CREATED=False\n'
printf 'PREFIX_CREATED=False\n'

printf '\nINSTALLER_STAGE_2D_BUILD_PASS=True\n'

progress_stage_complete "Build Wine 11.6"

if [ "$BUILD_ONLY" -eq 1 ]; then
    printf '\nV020_WINE_BUILD_ONLY_PASS=True\n'
    printf 'SOURCE_REUSABLE=%s\n' "$SOURCE"
    printf 'BUILD_REUSABLE=%s\n' "$BUILD"
    printf 'BUILD_LOG=%s\n' "$BUILD_LOG"
    echo 'Wine compilation and build-artifact validation completed.'
    echo 'No make install, Wine prefix creation or MU installation was started.'
    exit 0
fi

# === MU_INSTALLER_STAGE_2D_BUILD_END ===

# === MU_INSTALLER_STAGE_2E_RUNTIME_INSTALL_BEGIN ===

progress_stage_start "Install private Wine runtime"

INSTALL_LOG="$LOG_DIR/wine-${WINE_VERSION}-install.log"

log "Install private Wine ${WINE_VERSION} runtime"

[ -d "$BUILD" ] ||
    die "Wine build directory missing"

[ -f "$BUILD/Makefile" ] ||
    die "Wine build Makefile missing"

[ ! -e "$RUNTIME" ] ||
    die "runtime path already exists before make install: $RUNTIME"

[ ! -e "$PREFIX" ] ||
    die "Wine prefix unexpectedly exists before runtime installation"

INSTALL_START_EPOCH="$(date +%s)"

progress_install_heartbeat \
    "$$" \
    "$INSTALL_START_EPOCH" \
    "$INSTALL_LOG" &

INSTALL_HEARTBEAT_PID=$!

printf 'INSTALL_HEARTBEAT_PID=%s\n' \
    "$INSTALL_HEARTBEAT_PID"

set +e

make \
    -C "$BUILD" \
    install \
    >"$INSTALL_LOG" 2>&1

INSTALL_RC=$?

set -e

if kill -0 "$INSTALL_HEARTBEAT_PID" 2>/dev/null; then
    kill "$INSTALL_HEARTBEAT_PID" 2>/dev/null ||
        true
fi

wait "$INSTALL_HEARTBEAT_PID" 2>/dev/null ||
    true

progress_install_heartbeat_finish

INSTALL_END_EPOCH="$(date +%s)"
INSTALL_SECONDS="$((INSTALL_END_EPOCH - INSTALL_START_EPOCH))"

printf 'INSTALL_RC=%s\n' "$INSTALL_RC"
printf 'INSTALL_SECONDS=%s\n' "$INSTALL_SECONDS"

if [ "$INSTALL_RC" -ne 0 ]; then
    printf '\n--- INSTALL LOG TAIL ---\n'

    tail -n 120 \
        "$INSTALL_LOG" \
        || true

    if [ -e "$RUNTIME" ]; then
        FAILED_RUNTIME="${RUNTIME}.failed-install.$(date +%Y%m%d_%H%M%S)"

        mv -- \
            "$RUNTIME" \
            "$FAILED_RUNTIME"

        printf 'FAILED_RUNTIME_PRESERVED=%s\n' \
            "$FAILED_RUNTIME"
    fi

    die "Wine runtime installation failed with rc=$INSTALL_RC"
fi

printf 'MAKE_INSTALL_COMPLETED=True\n'

log "Validate private Wine executables"

REQUIRED_RUNTIME_EXECUTABLES=(
    "$RUNTIME/bin/wine"
    "$RUNTIME/bin/wineboot"
    "$RUNTIME/bin/wineserver"
)

for EXECUTABLE in "${REQUIRED_RUNTIME_EXECUTABLES[@]}"
do
    [ -x "$EXECUTABLE" ] ||
        die "required Wine executable missing: $EXECUTABLE"

    printf 'PRESENT %s\n' "$EXECUTABLE"
done

WINE_VERSION_OUTPUT="$(
    "$RUNTIME/bin/wine" --version
)"

printf 'PRIVATE_WINE_VERSION=%s\n' \
    "$WINE_VERSION_OUTPUT"

[ "$WINE_VERSION_OUTPUT" = "wine-${WINE_VERSION}" ] ||
    die "unexpected private Wine version: $WINE_VERSION_OUTPUT"

printf 'PRIVATE_WINE_VERSION_OK=True\n'

log "Validate installed runtime files"

REQUIRED_RUNTIME_FILES=(
    lib/wine/x86_64-unix/ntdll.so

    lib/wine/i386-windows/ntdll.dll
    lib/wine/x86_64-windows/ntdll.dll

    lib/wine/i386-windows/kernelbase.dll
    lib/wine/x86_64-windows/kernelbase.dll

    lib/wine/i386-windows/ntoskrnl.exe
    lib/wine/x86_64-windows/ntoskrnl.exe

    lib/wine/x86_64-unix/winepulse.so
    lib/wine/x86_64-unix/winealsa.so
)

for REL in "${REQUIRED_RUNTIME_FILES[@]}"
do
    [ -f "$RUNTIME/$REL" ] ||
        die "required runtime file missing: $REL"

    printf 'PRESENT %s\n' "$REL"
done

printf 'REQUIRED_RUNTIME_FILES_PRESENT=True\n'

log "Compare build artifacts with installed runtime"

BUILD_RUNTIME_PAIRS=(
    "dlls/ntdll/ntdll.so|lib/wine/x86_64-unix/ntdll.so"

    "dlls/ntdll/i386-windows/ntdll.dll|lib/wine/i386-windows/ntdll.dll"
    "dlls/ntdll/x86_64-windows/ntdll.dll|lib/wine/x86_64-windows/ntdll.dll"

    "dlls/kernelbase/i386-windows/kernelbase.dll|lib/wine/i386-windows/kernelbase.dll"
    "dlls/kernelbase/x86_64-windows/kernelbase.dll|lib/wine/x86_64-windows/kernelbase.dll"

    "dlls/ntoskrnl.exe/i386-windows/ntoskrnl.exe|lib/wine/i386-windows/ntoskrnl.exe"
    "dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe|lib/wine/x86_64-windows/ntoskrnl.exe"

    "dlls/winepulse.drv/winepulse.so|lib/wine/x86_64-unix/winepulse.so"
    "dlls/winealsa.drv/winealsa.so|lib/wine/x86_64-unix/winealsa.so"
)

for PAIR in "${BUILD_RUNTIME_PAIRS[@]}"
do
    BUILD_REL="${PAIR%%|*}"
    RUNTIME_REL="${PAIR#*|}"

    cmp -s \
        "$BUILD/$BUILD_REL" \
        "$RUNTIME/$RUNTIME_REL" ||
        die "installed artifact differs from build: $RUNTIME_REL"

    printf 'IDENTICAL %s -> %s\n' \
        "$BUILD_REL" \
        "$RUNTIME_REL"
done

printf 'BUILD_RUNTIME_ARTIFACTS_IDENTICAL=True\n'

log "Validate installed architectures"

file \
    "$RUNTIME/lib/wine/i386-windows/ntdll.dll" \
    "$RUNTIME/lib/wine/x86_64-windows/ntdll.dll" \
    "$RUNTIME/lib/wine/i386-windows/ntoskrnl.exe" \
    "$RUNTIME/lib/wine/x86_64-windows/ntoskrnl.exe" \
    "$RUNTIME/lib/wine/x86_64-unix/ntdll.so" \
    "$RUNTIME/lib/wine/x86_64-unix/winepulse.so" \
    "$RUNTIME/lib/wine/x86_64-unix/winealsa.so"

log "Record private runtime hashes"

sha256sum \
    "$RUNTIME/bin/wine" \
    "$RUNTIME/bin/wineserver" \
    "$RUNTIME/lib/wine/x86_64-unix/ntdll.so" \
    "$RUNTIME/lib/wine/i386-windows/ntdll.dll" \
    "$RUNTIME/lib/wine/x86_64-windows/ntdll.dll" \
    "$RUNTIME/lib/wine/i386-windows/kernelbase.dll" \
    "$RUNTIME/lib/wine/x86_64-windows/kernelbase.dll" \
    "$RUNTIME/lib/wine/i386-windows/ntoskrnl.exe" \
    "$RUNTIME/lib/wine/x86_64-windows/ntoskrnl.exe" \
    "$RUNTIME/lib/wine/x86_64-unix/winepulse.so" \
    "$RUNTIME/lib/wine/x86_64-unix/winealsa.so"

log "Prefix must still not exist"

[ ! -e "$PREFIX" ] ||
    die "Wine prefix was created during runtime installation"

printf 'PREFIX_CREATED=False\n'

printf '\nINSTALLER_STAGE_2E_RUNTIME_INSTALL_PASS=True\n'

progress_stage_complete "Install private Wine runtime"

if [ "$RUNTIME_ONLY" -eq 1 ]; then
    printf '\nV020_WINE_RUNTIME_ONLY_PASS=True\n'
    printf 'RUNTIME_READY=%s\n' "$RUNTIME"
    printf 'RUNTIME_INSTALL_LOG=%s\n' "$INSTALL_LOG"
    echo 'Private Wine runtime installed and checked against build artifacts.'
    echo 'No prefix creation, MU Online installation or GameGuard startup was attempted.'
    exit 0
fi

# === MU_INSTALLER_STAGE_2E_RUNTIME_INSTALL_END ===
fi # V020_PREFIX_ONLY_BYPASS_PREVIOUS_INSTALL_STAGES


if [ "$RESUME_FROM_PREFIX" -eq 0 ]; then

# === MU_INSTALLER_STAGE_3A_FRESH_PREFIX_BEGIN ===

progress_stage_start "Create Wine prefix"

WINEBOOT_LOG="$LOG_DIR/prefix-first-wineboot.log"

log "Pinned Wine runtime resolution"

[ -x "$RUNTIME/bin/wine" ] ||
    die "private wine missing"

[ -x "$RUNTIME/bin/wineboot" ] ||
    die "private wineboot missing"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver missing"

[ ! -e "$PREFIX" ] ||
    die "prefix already exists before first wineboot: $PREFIX"

WINE_RESOLVED="$(
    PATH="$PINNED_PATH" \
        command -v wine
)"

WINEBOOT_RESOLVED="$(
    PATH="$PINNED_PATH" \
        command -v wineboot
)"

WINESERVER_RESOLVED="$(
    PATH="$PINNED_PATH" \
        command -v wineserver
)"

printf 'WINE_RESOLVED=%s\n' "$WINE_RESOLVED"
printf 'WINEBOOT_RESOLVED=%s\n' "$WINEBOOT_RESOLVED"
printf 'WINESERVER_RESOLVED=%s\n' "$WINESERVER_RESOLVED"

[ "$(readlink -f "$WINE_RESOLVED")" = \
  "$(readlink -f "$RUNTIME/bin/wine")" ] ||
    die "PATH resolves wine outside private runtime"

[ "$(readlink -f "$WINEBOOT_RESOLVED")" = \
  "$(readlink -f "$RUNTIME/bin/wineboot")" ] ||
    die "PATH resolves wineboot outside private runtime"

[ "$(readlink -f "$WINESERVER_RESOLVED")" = \
  "$(readlink -f "$RUNTIME/bin/wineserver")" ] ||
    die "PATH resolves wineserver outside private runtime"

printf 'PINNED_PATH_RESOLUTION_OK=True\n'

log "Create fresh Wine prefix"

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    WINEDEBUG=-all \
    "$RUNTIME/bin/wineboot" \
    -u \
    >"$WINEBOOT_LOG" 2>&1 &

WINEBOOT_PID=$!

printf 'WINEBOOT_PID=%s\n' "$WINEBOOT_PID"
printf 'WINEBOOT_LOG=%s\n' "$WINEBOOT_LOG"

CUSTOM_PROCESS_SEEN=0
CUSTOM_SERVER_SEEN=0
FOREIGN_RUNTIME_SEEN=0

EXPECTED_SERVER="$(
    readlink -f "$RUNTIME/bin/wineserver"
)"

scan_prefix_runtime()
{
    for PROC in /proc/[0-9]*
    do
        PID="${PROC##*/}"

        [ -r "$PROC/environ" ] ||
            continue

        PFX="$(
            (
                cat "$PROC/environ" 2>/dev/null ||
                    true
            ) |
                tr '\0' '\n' |
                sed -n 's/^WINEPREFIX=//p'
        )"

        [ "$PFX" = "$PREFIX" ] ||
            continue

        COMM="$(
            cat "$PROC/comm" 2>/dev/null ||
                true
        )"

        EXE="$(
            readlink -f "$PROC/exe" 2>/dev/null ||
                true
        )"

        printf 'PREFIX_PROCESS PID=%s COMM=%s EXE=%s\n' \
            "$PID" \
            "$COMM" \
            "${EXE:-UNAVAILABLE}"

        if [ -n "$EXE" ]; then
            case "$EXE" in
                "$RUNTIME"/*)
                    CUSTOM_PROCESS_SEEN=1
                    ;;

                *)
                    FOREIGN_RUNTIME_SEEN=1
                    printf 'FOREIGN_RUNTIME_PROCESS=%s\n' "$EXE"
                    ;;
            esac
        fi

        if [ "$COMM" = "wineserver" ]; then
            if [ "$EXE" = "$EXPECTED_SERVER" ]; then
                CUSTOM_SERVER_SEEN=1
            else
                FOREIGN_RUNTIME_SEEN=1
            fi
        fi
    done
}

for ((ATTEMPT=1; ATTEMPT<=50; ATTEMPT++))
do
    scan_prefix_runtime

    if [ "$CUSTOM_SERVER_SEEN" -eq 1 ]; then
        break
    fi

    if ! kill -0 "$WINEBOOT_PID" 2>/dev/null; then
        break
    fi

    sleep 0.1
done

set +e

wait "$WINEBOOT_PID"
WINEBOOT_RC=$?

set -e

# One final scan while Wine services are normally still alive.
scan_prefix_runtime

printf 'WINEBOOT_RC=%s\n' "$WINEBOOT_RC"
printf 'CUSTOM_PROCESS_SEEN=%s\n' "$CUSTOM_PROCESS_SEEN"
printf 'CUSTOM_SERVER_SEEN=%s\n' "$CUSTOM_SERVER_SEEN"
printf 'FOREIGN_RUNTIME_SEEN=%s\n' "$FOREIGN_RUNTIME_SEEN"

if [ "$WINEBOOT_RC" -ne 0 ]; then
    printf '\n--- WINEBOOT LOG TAIL ---\n'

    tail -n 120 \
        "$WINEBOOT_LOG" \
        || true

    env \
        WINEPREFIX="$PREFIX" \
        PATH="$PINNED_PATH" \
        WINESERVER="$RUNTIME/bin/wineserver" \
        "$RUNTIME/bin/wineserver" \
        -k \
        2>/dev/null ||
        true

    if [ -e "$PREFIX" ]; then
        FAILED_PREFIX="${PREFIX}.failed-wineboot.$(date +%Y%m%d_%H%M%S)"

        mv -- \
            "$PREFIX" \
            "$FAILED_PREFIX"

        printf 'FAILED_PREFIX_PRESERVED=%s\n' \
            "$FAILED_PREFIX"
    fi

    die "first wineboot failed with rc=$WINEBOOT_RC"
fi

[ "$CUSTOM_PROCESS_SEEN" -eq 1 ] ||
    die "no private-runtime Wine process observed during prefix creation"

[ "$CUSTOM_SERVER_SEEN" -eq 1 ] ||
    die "private wineserver was not observed during prefix creation"

[ "$FOREIGN_RUNTIME_SEEN" -eq 0 ] ||
    die "foreign Wine runtime was observed during prefix creation"

printf 'FIRST_WINEBOOT_RUNTIME_OWNERSHIP_OK=True\n'

log "Wait for Wine prefix initialization to finish"

# wineboot -u can exit successfully while Wine services are still populating
# the new prefix, including the 32-bit SysWOW64 directory. Never call
# wineserver -k on the successful initialization path: it can interrupt
# that work and leave an incomplete WoW64 prefix.
if timeout 300 env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    WINEDEBUG=-all \
    "$RUNTIME/bin/wineserver" \
    -w \
    >>"$WINEBOOT_LOG" 2>&1
then
    printf 'PREFIX_WINESERVER_WAIT_RC=0\n'
else
    PREFIX_WINESERVER_WAIT_RC=$?
    printf 'PREFIX_WINESERVER_WAIT_RC=%s\n' "$PREFIX_WINESERVER_WAIT_RC"
    printf '\n--- WINEBOOT LOG TAIL ---\n'
    tail -n 120 "$WINEBOOT_LOG" || true
    die "prefix initialization did not finish cleanly (wineserver -w rc=$PREFIX_WINESERVER_WAIT_RC)"
fi

printf 'PREFIX_WINESERVER_STOPPED=True\n'

log "Validate pristine prefix"

[ -d "$PREFIX" ] ||
    die "prefix directory missing after wineboot"

[ -f "$PREFIX/system.reg" ] ||
    die "system.reg missing"

[ -f "$PREFIX/user.reg" ] ||
    die "user.reg missing"

[ -f "$PREFIX/userdef.reg" ] ||
    die "userdef.reg missing"

[ -d "$PREFIX/drive_c/windows/system32" ] ||
    die "system32 missing"

[ -d "$PREFIX/drive_c/windows/syswow64" ] ||
    die "syswow64 missing"

[ -f "$PREFIX/drive_c/windows/system32/notepad.exe" ] ||
    die "64-bit notepad missing"

[ -f "$PREFIX/drive_c/windows/syswow64/notepad.exe" ] ||
    die "32-bit notepad missing"

SYS32_NOTEPAD="$(
    file -b \
        "$PREFIX/drive_c/windows/system32/notepad.exe"
)"

WOW64_NOTEPAD="$(
    file -b \
        "$PREFIX/drive_c/windows/syswow64/notepad.exe"
)"

printf 'SYSTEM32_NOTEPAD=%s\n' "$SYS32_NOTEPAD"
printf 'SYSWOW64_NOTEPAD=%s\n' "$WOW64_NOTEPAD"

case "$SYS32_NOTEPAD" in
    *PE32+*x86-64*)
        ;;
    *)
        die "system32 notepad is not x86_64"
        ;;
esac

case "$WOW64_NOTEPAD" in
    *PE32*Intel*i386*)
        ;;
    *)
        die "syswow64 notepad is not i386"
        ;;
esac

printf 'WOW64_PREFIX_LAYOUT_OK=True\n'

log "Verify MU and GameGuard are still absent"

[ ! -e "$MU_DIR" ] ||
    die "MU directory unexpectedly exists in pristine prefix"

if grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null
then
    die "GGKernel64 service unexpectedly exists in pristine prefix"
fi

GG_FILE="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$GG_FILE" ] ||
    die "GGKernel64.sys unexpectedly exists in pristine prefix"

printf 'MU_PRESENT=False\n'
printf 'GGKERNEL64_SERVICE_PRESENT=False\n'
printf 'GGKERNEL64_SYS_PRESENT=False\n'

log "Verify prefix is idle"

ACTIVE_PREFIX_PROCESS=0

for PROC in /proc/[0-9]*
do
    [ -r "$PROC/environ" ] ||
        continue

    PFX="$(
        (
            cat "$PROC/environ" 2>/dev/null ||
                true
        ) |
            tr '\0' '\n' |
            sed -n 's/^WINEPREFIX=//p'
    )"

    if [ "$PFX" = "$PREFIX" ]; then
        ACTIVE_PREFIX_PROCESS=1

        printf 'ACTIVE_PREFIX_PROCESS PID=%s\n' \
            "${PROC##*/}"
    fi
done

[ "$ACTIVE_PREFIX_PROCESS" -eq 0 ] ||
    die "prefix still has active Wine processes"

printf 'PREFIX_IDLE=True\n'

printf '\nINSTALLER_STAGE_3A_FRESH_PREFIX_PASS=True\n'
printf 'PREFIX_CREATED_FROM_ZERO=True\n'
printf 'PINNED_RUNTIME_FROM_FIRST_WINEBOOT=True\n'

progress_stage_complete "Create Wine prefix"

# === MU_INSTALLER_STAGE_3A_FRESH_PREFIX_END ===

if [ "$PREFIX_ONLY" -eq 1 ]; then
    printf '\nV020_WINE_PREFIX_ONLY_PASS=True\n'
    printf 'PREFIX_READY=%s\n' "$PREFIX"
    echo 'Pristine private WoW64 Wine prefix initialized; MU remains uninstalled.'
    exit 0
fi

fi # V020_SKIP_PREFIX_INITIALIZATION_WHEN_RESUMING

# === MU_INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_BEGIN ===

progress_stage_start "Install MU Online"

TESTED_MU_INSTALLER_SHA256="8219cae729d8b09fffc07eca9893e0e6365cc0549f0a449a1e2489b1a2253df9"

TESTED_MU_EXE_SHA256="c1b822ba4e9d24241a9a7c78afdaac82222505e716c7785dca21f27466f19e23"

TESTED_MAIN_EXE_INSTALLER_SHA256="be1cf29eedf6a4c43b93c3b6d9b59e45d271294eb3e37c6370f09a3724c0d8f9"

MU_INSTALL_LOG="$LOG_DIR/mu-official-installer.log"

log "Official MU installer preflight"

[ -d "$PREFIX" ] ||
    die "Wine prefix missing"

[ -f "$PREFIX/system.reg" ] ||
    die "prefix system.reg missing"

[ -x "$RUNTIME/bin/wine" ] ||
    die "private Wine missing"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver missing"

[ -f "$INSTALLER" ] ||
    die "MU installer missing: $INSTALLER"

[ ! -e "$MU_DIR" ] ||
    die "MU directory already exists before official installer"

if grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null
then
    die "GGKernel64 service already exists before MU installation"
fi

PREINSTALL_GG_FILE="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$PREINSTALL_GG_FILE" ] ||
    die "GGKernel64.sys already exists before MU installation"

printf 'PREINSTALL_MU_PRESENT=False\n'
printf 'PREINSTALL_GGKERNEL64_SERVICE_PRESENT=False\n'
printf 'PREINSTALL_GGKERNEL64_SYS_PRESENT=False\n'

log "Ensure prefix is idle before installer"

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    "$RUNTIME/bin/wineserver" \
    -w

printf 'PREFIX_IDLE_BEFORE_MU_INSTALL=True\n'

log "Record supplied MU installer"

INSTALLER_SHA256="$(
    sha256sum "$INSTALLER" |
        awk '{print $1}'
)"

INSTALLER_BYTES="$(
    stat -c '%s' "$INSTALLER"
)"

printf 'MU_INSTALLER=%s\n' "$INSTALLER"
printf 'MU_INSTALLER_BYTES=%s\n' "$INSTALLER_BYTES"
printf 'MU_INSTALLER_SHA256=%s\n' "$INSTALLER_SHA256"

if [ "$INSTALLER_SHA256" = "$TESTED_MU_INSTALLER_SHA256" ]; then
    TESTED_INSTALLER=1
    printf 'MU_INSTALLER_MATCHES_TESTED_BUILD=True\n'
else
    TESTED_INSTALLER=0
    printf 'MU_INSTALLER_MATCHES_TESTED_BUILD=False\n'
    printf 'WARNING: installer differs from the build used for the verified reference reproduction.\n'
fi

log "Run official MU installer"

printf '\n'
printf 'Complete the graphical MU installer normally.\n'
printf 'Keep the default installation directory:\n'
printf '  C:\\Program Files (x86)\\Webzen\\Mu\n'
printf '\n'
printf 'Do not launch MU automatically when installation finishes.\n'
printf '\n'

INSTALL_START_EPOCH="$(date +%s)"

set +e

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    WINEDEBUG=-all \
    "$RUNTIME/bin/wine" \
    "$INSTALLER" \
    >"$MU_INSTALL_LOG" 2>&1

MU_INSTALLER_RC=$?

set -e

printf 'MU_INSTALLER_RC=%s\n' "$MU_INSTALLER_RC"

if [ "$MU_INSTALLER_RC" -ne 0 ]; then
    printf '\n--- MU INSTALLER LOG TAIL ---\n'

    tail -n 120 \
        "$MU_INSTALL_LOG" \
        || true

    env \
        WINEPREFIX="$PREFIX" \
        PATH="$PINNED_PATH" \
        WINESERVER="$RUNTIME/bin/wineserver" \
        "$RUNTIME/bin/wineserver" \
        -k \
        2>/dev/null ||
        true

    die "MU installer failed with rc=$MU_INSTALLER_RC"
fi

log "Wait for installer child processes"

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    "$RUNTIME/bin/wineserver" \
    -w

INSTALL_END_EPOCH="$(date +%s)"
MU_INSTALL_SECONDS="$((INSTALL_END_EPOCH - INSTALL_START_EPOCH))"

printf 'MU_INSTALL_SECONDS=%s\n' "$MU_INSTALL_SECONDS"
printf 'PREFIX_IDLE_AFTER_MU_INSTALL=True\n'

log "Validate installed MU client"

MU_EXE="$MU_DIR/Mu.exe"
MAIN_EXE="$MU_DIR/main.exe"

[ -d "$MU_DIR" ] ||
    die "MU installation directory missing"

[ -f "$MU_EXE" ] ||
    die "Mu.exe missing after installation"

[ -f "$MAIN_EXE" ] ||
    die "main.exe missing after installation"

MU_EXE_DESC="$(
    file -b "$MU_EXE"
)"

MAIN_EXE_DESC="$(
    file -b "$MAIN_EXE"
)"

printf 'MU_EXE_FILE=%s\n' "$MU_EXE_DESC"
printf 'MAIN_EXE_FILE=%s\n' "$MAIN_EXE_DESC"

case "$MU_EXE_DESC" in
    *PE32*Intel*i386*)
        ;;
    *)
        die "Mu.exe has unexpected architecture"
        ;;
esac

case "$MAIN_EXE_DESC" in
    *PE32*Intel*i386*)
        ;;
    *)
        die "main.exe has unexpected architecture"
        ;;
esac

printf 'MU_CLIENT_ARCHITECTURES_OK=True\n'

MU_EXE_SHA256="$(
    sha256sum "$MU_EXE" |
        awk '{print $1}'
)"

MAIN_EXE_SHA256="$(
    sha256sum "$MAIN_EXE" |
        awk '{print $1}'
)"

printf 'MU_EXE_SHA256=%s\n' "$MU_EXE_SHA256"
printf 'MAIN_EXE_SHA256=%s\n' "$MAIN_EXE_SHA256"

if [ "$TESTED_INSTALLER" -eq 1 ]; then
    [ "$MU_EXE_SHA256" = "$TESTED_MU_EXE_SHA256" ] ||
        die "Mu.exe hash differs from verified installer output"

    [ "$MAIN_EXE_SHA256" = "$TESTED_MAIN_EXE_INSTALLER_SHA256" ] ||
        die "main.exe hash differs from verified installer output"

    printf 'TESTED_INSTALLER_CLIENT_HASHES_OK=True\n'
else
    printf 'TESTED_INSTALLER_CLIENT_HASHES_OK=NotApplicable\n'
fi

log "Verify GameGuard has not started"

GG_DIR="$MU_DIR/GameGuard"

if [ -d "$GG_DIR" ]; then
    die "GameGuard directory already exists; MU may have been launched during installation"
fi

if grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null
then
    die "GGKernel64 service exists before compatibility service setup"
fi

POSTINSTALL_GG_FILE="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$POSTINSTALL_GG_FILE" ] ||
    die "GGKernel64.sys exists before first MU launch"

printf 'GAMEGUARD_DIRECTORY_PRESENT=False\n'
printf 'GGKERNEL64_SERVICE_PRESENT=False\n'
printf 'GGKERNEL64_SYS_PRESENT=False\n'
printf 'GAMEGUARD_PRELAUNCH_BASELINE_OK=True\n'

log "Final prefix process check"

ACTIVE_PREFIX_PROCESS=0

for PROC in /proc/[0-9]*
do
    [ -r "$PROC/environ" ] ||
        continue

    PFX="$(
        (
            cat "$PROC/environ" 2>/dev/null ||
                true
        ) |
            tr '\0' '\n' |
            sed -n 's/^WINEPREFIX=//p'
    )"

    if [ "$PFX" = "$PREFIX" ]; then
        ACTIVE_PREFIX_PROCESS=1

        printf 'ACTIVE_PREFIX_PROCESS PID=%s\n' \
            "${PROC##*/}"
    fi
done

[ "$ACTIVE_PREFIX_PROCESS" -eq 0 ] ||
    die "Wine processes remain after official installer"

printf 'PREFIX_IDLE=True\n'

printf '\nINSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_PASS=True\n'
printf 'OFFICIAL_MU_INSTALL_COMPLETED=True\n'
printf 'DRIVER_COPIED=False\n'
printf 'SERVICE_SEEDED=False\n'
printf 'MU_STARTED=False\n'
printf 'GAMEGUARD_STARTED=False\n'

progress_stage_complete "Install MU Online"

# === MU_INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_END ===

# === MU_INSTALLER_STAGE_3C_GGKERNEL64_SEED_BEGIN ===

progress_stage_start "Configure GameGuard service record"

GG_QUERY_LOG="$LOG_DIR/ggkernel64-service-query.log"

log "GGKernel64 Wine SCM compatibility setup preflight"

[ -d "$PREFIX" ] ||
    die "Wine prefix missing"

[ -f "$PREFIX/system.reg" ] ||
    die "system.reg missing"

[ -f "$PREFIX/user.reg" ] ||
    die "user.reg missing"

[ -f "$PREFIX/userdef.reg" ] ||
    die "userdef.reg missing"

[ -f "$MU_DIR/Mu.exe" ] ||
    die "Mu.exe missing"

[ -f "$MU_DIR/main.exe" ] ||
    die "main.exe missing"

[ -x "$RUNTIME/bin/wine" ] ||
    die "private Wine missing"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver missing"

if [ -d "$MU_DIR/GameGuard" ]; then
    die "GameGuard directory already exists before service seed"
fi

if grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null
then
    die "GGKernel64 service already exists before service seed"
fi

PRESEED_DRIVER="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$PRESEED_DRIVER" ] ||
    die "GGKernel64.sys already exists before service seed"

printf 'PRESEED_GAMEGUARD_DIRECTORY_PRESENT=False\n'
printf 'PRESEED_GGKERNEL64_SERVICE_PRESENT=False\n'
printf 'PRESEED_GGKERNEL64_SYS_PRESENT=False\n'

log "Ensure prefix is idle before registry modification"

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    "$RUNTIME/bin/wineserver" \
    -w

printf 'PREFIX_IDLE_BEFORE_SERVICE_SEED=True\n'

log "Backup prefix registry before service seed"

GG_SEED_BACKUP="$BASE/backups/pre-ggkernel64-seed-$(date +%Y%m%d_%H%M%S)"

[ ! -e "$GG_SEED_BACKUP" ] ||
    die "registry backup path already exists: $GG_SEED_BACKUP"

mkdir -p "$GG_SEED_BACKUP"

cp -a \
    "$PREFIX/system.reg" \
    "$PREFIX/user.reg" \
    "$PREFIX/userdef.reg" \
    "$GG_SEED_BACKUP/"

cmp -s \
    "$PREFIX/system.reg" \
    "$GG_SEED_BACKUP/system.reg" ||
    die "system.reg backup verification failed"

cmp -s \
    "$PREFIX/user.reg" \
    "$GG_SEED_BACKUP/user.reg" ||
    die "user.reg backup verification failed"

cmp -s \
    "$PREFIX/userdef.reg" \
    "$GG_SEED_BACKUP/userdef.reg" ||
    die "userdef.reg backup verification failed"

printf 'GG_SERVICE_SEED_REGISTRY_BACKUP=%s\n' \
    "$GG_SEED_BACKUP"

printf 'GG_SERVICE_SEED_REGISTRY_BACKUP_OK=True\n'

rollback_ggkernel64_seed()
{
    REASON="$1"

    printf '\nROLLBACK_REASON=%s\n' "$REASON"

    env \
        WINEPREFIX="$PREFIX" \
        PATH="$PINNED_PATH" \
        WINESERVER="$RUNTIME/bin/wineserver" \
        "$RUNTIME/bin/wineserver" \
        -k \
        2>/dev/null ||
        true

    env \
        WINEPREFIX="$PREFIX" \
        PATH="$PINNED_PATH" \
        WINESERVER="$RUNTIME/bin/wineserver" \
        "$RUNTIME/bin/wineserver" \
        -w \
        2>/dev/null ||
        true

    cp -a \
        "$GG_SEED_BACKUP/system.reg" \
        "$PREFIX/system.reg"

    cp -a \
        "$GG_SEED_BACKUP/user.reg" \
        "$PREFIX/user.reg"

    cp -a \
        "$GG_SEED_BACKUP/userdef.reg" \
        "$PREFIX/userdef.reg"

    printf 'GG_SERVICE_SEED_ROLLED_BACK=True\n'

    die "$REASON"
}

wine_reg_add()
{
    VALUE_NAME="$1"
    VALUE_TYPE="$2"
    VALUE_DATA="$3"

    if ! env \
        WINEPREFIX="$PREFIX" \
        PATH="$PINNED_PATH" \
        WINESERVER="$RUNTIME/bin/wineserver" \
        WINEDEBUG=-all \
        "$RUNTIME/bin/wine" \
        reg.exe add \
        "$GG_SERVICE" \
        /v "$VALUE_NAME" \
        /t "$VALUE_TYPE" \
        /d "$VALUE_DATA" \
        /f \
        >/dev/null 2>&1
    then
        rollback_ggkernel64_seed \
            "failed to write GGKernel64 registry value: $VALUE_NAME"
    fi

    printf 'GG_SERVICE_VALUE_WRITTEN=%s\n' \
        "$VALUE_NAME"
}

log "Seed GGKernel64 compatibility service record"

wine_reg_add \
    DisplayName \
    REG_SZ \
    GGKernel64

wine_reg_add \
    ErrorControl \
    REG_DWORD \
    1

wine_reg_add \
    ImagePath \
    REG_EXPAND_SZ \
    "$GG_IMAGE_PATH"

wine_reg_add \
    Start \
    REG_DWORD \
    3

wine_reg_add \
    Type \
    REG_DWORD \
    1

printf 'GGKERNEL64_SERVICE_VALUES_WRITTEN=5\n'

log "Validate live registry record"

if ! env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    WINEDEBUG=-all \
    "$RUNTIME/bin/wine" \
    reg.exe query \
    "$GG_SERVICE" \
    >"$GG_QUERY_LOG" 2>&1
then
    rollback_ggkernel64_seed \
        "GGKernel64 service query failed"
fi

cat "$GG_QUERY_LOG"

if ! python3 - \
    "$GG_QUERY_LOG" \
    "$GG_IMAGE_PATH" <<'PY'
from pathlib import Path
import sys

query_path = Path(sys.argv[1])
expected_image = sys.argv[2]

text = query_path.read_text(errors="replace")

wanted = {
    "DisplayName": ("REG_SZ", "GGKernel64"),
    "ErrorControl": ("REG_DWORD", "0x1"),
    "ImagePath": ("REG_EXPAND_SZ", expected_image),
    "Start": ("REG_DWORD", "0x3"),
    "Type": ("REG_DWORD", "0x1"),
}

found = {}

for raw in text.splitlines():
    line = raw.strip()

    if not line:
        continue

    parts = line.split(None, 2)

    if len(parts) != 3:
        continue

    name, value_type, value_data = parts

    if name in wanted:
        found[name] = (value_type, value_data)

missing = sorted(set(wanted) - set(found))

if missing:
    raise SystemExit(
        "missing GGKernel64 values: " + ", ".join(missing)
    )

for name, expected in wanted.items():
    actual = found[name]

    if actual != expected:
        raise SystemExit(
            f"{name}: expected {expected!r}, got {actual!r}"
        )

print("GGKERNEL64_LIVE_SERVICE_RECORD_OK=True")
PY
then
    rollback_ggkernel64_seed \
        "GGKernel64 live service record validation failed"
fi


log "Fully stop Wine after service seed"

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    "$RUNTIME/bin/wineserver" \
    -k \
    2>/dev/null ||
    true

env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    "$RUNTIME/bin/wineserver" \
    -w \
    2>/dev/null ||
    die "Wine did not stop after GGKernel64 service seed"

printf 'WINE_FULLY_STOPPED_AFTER_SEED=True\n'

log "Verify prefix has no active processes"

ACTIVE_PREFIX_PROCESS=0

for PROC in /proc/[0-9]*
do
    [ -r "$PROC/environ" ] ||
        continue

    PFX="$(
        (
            cat "$PROC/environ" 2>/dev/null ||
                true
        ) |
            tr '\0' '\n' |
            sed -n 's/^WINEPREFIX=//p'
    )"

    if [ "$PFX" = "$PREFIX" ]; then
        ACTIVE_PREFIX_PROCESS=1

        printf 'ACTIVE_PREFIX_PROCESS PID=%s\n' \
            "${PROC##*/}"
    fi
done

[ "$ACTIVE_PREFIX_PROCESS" -eq 0 ] ||
    die "Wine processes remain after GGKernel64 service seed"

printf 'PREFIX_IDLE_AFTER_SERVICE_SEED=True\n'

log "Validate persisted offline service record"

if ! python3 - \
    "$PREFIX/system.reg" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

lines = path.read_text(
    errors="replace"
).splitlines()

section_re = re.compile(
    r'^\[System\\\\ControlSet[0-9]+\\\\Services\\\\GGKernel64\]'
)

starts = [
    i
    for i, line in enumerate(lines)
    if section_re.match(line)
]

if len(starts) != 1:
    raise SystemExit(
        f"expected one persisted GGKernel64 section, found {len(starts)}"
    )

start = starts[0]

end = len(lines)

for i in range(start + 1, len(lines)):
    if lines[i].startswith("["):
        end = i
        break

section = "\n".join(lines[start:end])

required = (
    '"DisplayName"="GGKernel64"',
    '"ErrorControl"=dword:00000001',
    '"Start"=dword:00000003',
    '"Type"=dword:00000001',
    '"ImagePath"=str(2):',
    'Program Files (x86)',
    'Webzen',
    'GameGuard',
    'GGKernel64.sys',
)

for marker in required:
    if marker not in section:
        raise SystemExit(
            f"offline GGKernel64 record missing marker: {marker}"
        )

print("GGKERNEL64_OFFLINE_SERVICE_RECORD_OK=True")
PY
then
    rollback_ggkernel64_seed \
        "GGKernel64 offline service record validation failed"
fi


log "Verify no GameGuard driver was supplied by installer"

[ ! -d "$MU_DIR/GameGuard" ] ||
    die "GameGuard directory unexpectedly exists after service seed"

POSTSEED_DRIVER="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$POSTSEED_DRIVER" ] ||
    die "GGKernel64.sys unexpectedly exists after service seed"

printf 'GAMEGUARD_DIRECTORY_PRESENT=False\n'
printf 'GGKERNEL64_SYS_PRESENT=False\n'
printf 'DRIVER_COPIED=False\n'

printf '\nINSTALLER_STAGE_3C_GGKERNEL64_SEED_PASS=True\n'
printf 'SERVICE_RECORD_SEEDED=True\n'
printf 'WINE_FULLY_STOPPED_AFTER_SEED=True\n'
printf 'FINAL_PRELAUNCH_STATE_READY=True\n'

progress_stage_complete "Configure GameGuard service record"

# === MU_INSTALLER_STAGE_3C_GGKERNEL64_SEED_END ===

# === MU_INSTALLER_STAGE_3D_LAUNCHER_BEGIN ===

progress_stage_start "Create MU Online launcher"

LAUNCHER="$BIN_DIR/mu-online"

log "Create pinned MU Online launcher"

[ -d "$BIN_DIR" ] ||
    die "bin directory missing"

[ -x "$RUNTIME/bin/wine" ] ||
    die "private Wine missing before launcher creation"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver missing before launcher creation"

[ -d "$PREFIX" ] ||
    die "Wine prefix missing before launcher creation"

[ -f "$MU_DIR/Mu.exe" ] ||
    die "Mu.exe missing before launcher creation"

[ -f "$MU_DIR/main.exe" ] ||
    die "main.exe missing before launcher creation"

grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null ||
    die "GGKernel64 compatibility service record missing"

if [ -e "$LAUNCHER" ]; then
    die "launcher already exists: $LAUNCHER"
fi

cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/usr/bin/env bash

set -euo pipefail

SELF="$(
    readlink -f -- "${BASH_SOURCE[0]}"
)"

BIN_DIR="$(
    cd -- "$(dirname -- "$SELF")" &&
    pwd
)"

BASE="$(
    cd -- "$BIN_DIR/.." &&
    pwd
)"

WINE_VERSION="11.6"

RUNTIME="$BASE/runtime/wine-${WINE_VERSION}-mu"
PREFIX="$BASE/prefix"

MU_DIR="$PREFIX/drive_c/Program Files (x86)/Webzen/Mu"
MU_EXE="$MU_DIR/Mu.exe"
MAIN_EXE="$MU_DIR/main.exe"

PINNED_PATH="$RUNTIME/bin:/usr/local/bin:/usr/bin:/bin"

die()
{
    printf 'MU Online launcher: %s\n' "$*" >&2
    exit 1
}

[ -x "$RUNTIME/bin/wine" ] ||
    die "private Wine runtime is missing"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver is missing"

[ -d "$PREFIX" ] ||
    die "Wine prefix is missing"

[ -f "$PREFIX/system.reg" ] ||
    die "Wine registry is missing"

[ -f "$MU_EXE" ] ||
    die "Mu.exe is missing"

[ -f "$MAIN_EXE" ] ||
    die "main.exe is missing"

grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null ||
    die "GGKernel64 Wine SCM compatibility record is missing"

RESOLVED_WINE="$(
    PATH="$PINNED_PATH" \
        command -v wine
)"

RESOLVED_SERVER="$(
    PATH="$PINNED_PATH" \
        command -v wineserver
)"

[ "$(readlink -f "$RESOLVED_WINE")" = \
  "$(readlink -f "$RUNTIME/bin/wine")" ] ||
    die "PATH resolves wine outside the private runtime"

[ "$(readlink -f "$RESOLVED_SERVER")" = \
  "$(readlink -f "$RUNTIME/bin/wineserver")" ] ||
    die "PATH resolves wineserver outside the private runtime"

DEBUG="${MU_WINEDEBUG:--all}"

cd "$MU_DIR"

exec env \
    WINEPREFIX="$PREFIX" \
    PATH="$PINNED_PATH" \
    WINESERVER="$RUNTIME/bin/wineserver" \
    WINEDEBUG="$DEBUG" \
    "$RUNTIME/bin/wine" \
    ./Mu.exe \
    "$@"
LAUNCHER_EOF

chmod 0755 "$LAUNCHER"

log "Validate launcher"

bash -n "$LAUNCHER" ||
    die "generated launcher has invalid shell syntax"

[ -x "$LAUNCHER" ] ||
    die "launcher is not executable"

grep -F \
    'exec env' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher exec command missing"

grep -F \
    '"$RUNTIME/bin/wine"' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not use absolute private Wine"

grep -F \
    'WINESERVER="$RUNTIME/bin/wineserver"' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not pin WINESERVER"

grep -F \
    './Mu.exe' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not start Mu.exe"

if grep -Ei \
    'reg(\.exe)?[[:space:]]+add|GGKernel64\.sys|cp[[:space:]].*GGKernel' \
    "$LAUNCHER" \
    >/dev/null
then
    die "launcher contains forbidden service/driver mutation logic"
fi

printf 'LAUNCHER_MUTATES_GGKERNEL64_SERVICE=False\n'
printf 'LAUNCHER_COPIES_GGKERNEL64_DRIVER=False\n'
printf 'LAUNCHER_RESTARTS_WINESERVER=False\n'
printf 'LAUNCHER_USES_ABSOLUTE_PRIVATE_WINE=True\n'
printf 'LAUNCHER_PINS_WINESERVER=True\n'

printf 'MU_LAUNCHER=%s\n' "$LAUNCHER"

printf '\nINSTALLER_STAGE_3D_LAUNCHER_PASS=True\n'
printf 'GAME_STARTED=False\n'

progress_stage_complete "Create MU Online launcher"

# === MU_INSTALLER_STAGE_3D_LAUNCHER_END ===

# === MU_INSTALLER_STAGE_3E_DESKTOP_INTEGRATION_BEGIN ===

progress_stage_start "Desktop integration"

log "Create MU Online desktop integration"

APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
APPLICATION_ENTRY="$APPLICATIONS_DIR/mu-online.desktop"

DESKTOP_DIR=""

if command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_DIR="$(
        xdg-user-dir DESKTOP 2>/dev/null ||
        true
    )"
fi

if [ -z "$DESKTOP_DIR" ] ||
   [ "$DESKTOP_DIR" = "$HOME" ]
then
    if [ -d "$HOME/Desktop" ]; then
        DESKTOP_DIR="$HOME/Desktop"
    elif [ -d "$HOME/Pulpit" ]; then
        DESKTOP_DIR="$HOME/Pulpit"
    else
        die "cannot determine desktop directory"
    fi
fi

mkdir -p \
    "$APPLICATIONS_DIR" \
    "$DESKTOP_DIR"

DESKTOP_ENTRY="$DESKTOP_DIR/MU Online.desktop"
LEGACY_DESKTOP="$DESKTOP_DIR/Mu.desktop"

ICON_NAME="applications-games"
LEGACY_WINE_DESKTOP_ARCHIVED=False

if [ -f "$LEGACY_DESKTOP" ] &&
   grep -Fiq \
       'Mu.lnk' \
       "$LEGACY_DESKTOP" &&
   grep -Eq \
       '^Exec=env[[:space:]].*WINEPREFIX=.*[[:space:]]wine[[:space:]]' \
       "$LEGACY_DESKTOP"
then
    LEGACY_ICON="$(
        awk '
            /^Icon=/ {
                sub(/^Icon=/, "")
                print
                exit
            }
        ' "$LEGACY_DESKTOP"
    )"

    if [ -n "$LEGACY_ICON" ]; then
        ICON_NAME="$LEGACY_ICON"
    fi

    DESKTOP_BACKUP_DIR="$BASE/backups/desktop-shortcuts/$(date +%Y%m%d_%H%M%S)-$$"

    mkdir -p "$DESKTOP_BACKUP_DIR"

    mv -- \
        "$LEGACY_DESKTOP" \
        "$DESKTOP_BACKUP_DIR/Mu.desktop"

    LEGACY_WINE_DESKTOP_ARCHIVED=True
fi

for MANAGED_TARGET in \
    "$APPLICATION_ENTRY" \
    "$DESKTOP_ENTRY"
do
    if [ -e "$MANAGED_TARGET" ] &&
       ! grep -Fqx \
           'X-MUOnline-Linux-Managed=true' \
           "$MANAGED_TARGET"
    then
        die "refusing to overwrite unmanaged desktop entry: $MANAGED_TARGET"
    fi
done

DESKTOP_EXEC="$(
    python3 - "$LAUNCHER" <<'PY_DESKTOP_EXEC'
import sys

value = sys.argv[1]

if "\n" in value or "\r" in value:
    raise SystemExit("launcher path contains a newline")

for char in ("\\", '"', "`", "$"):
    value = value.replace(char, "\\" + char)

print(value)
PY_DESKTOP_EXEC
)"

cat > "$APPLICATION_ENTRY" <<DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MU Online
Comment=Launch MU Online with its private Wine runtime
Exec="$DESKTOP_EXEC"
Icon=$ICON_NAME
Terminal=false
StartupNotify=true
Categories=Game;
StartupWMClass=mu.exe
X-MUOnline-Linux-Managed=true
DESKTOP_EOF

chmod 0644 "$APPLICATION_ENTRY"

cp -- \
    "$APPLICATION_ENTRY" \
    "$DESKTOP_ENTRY"

chmod 0755 "$DESKTOP_ENTRY"

[ -f "$APPLICATION_ENTRY" ] ||
    die "application menu entry was not created"

[ -x "$DESKTOP_ENTRY" ] ||
    die "desktop launcher was not created as executable"

grep -Fqx \
    "Exec=\"$DESKTOP_EXEC\"" \
    "$APPLICATION_ENTRY" ||
    die "application menu entry does not use private launcher"

grep -Fqx \
    "Exec=\"$DESKTOP_EXEC\"" \
    "$DESKTOP_ENTRY" ||
    die "desktop entry does not use private launcher"

grep -Fqx \
    'X-MUOnline-Linux-Managed=true' \
    "$APPLICATION_ENTRY" ||
    die "application menu entry lacks managed marker"

grep -Fqx \
    'X-MUOnline-Linux-Managed=true' \
    "$DESKTOP_ENTRY" ||
    die "desktop entry lacks managed marker"

printf 'APPLICATION_MENU_ENTRY=%s\n' \
    "$APPLICATION_ENTRY"

printf 'DESKTOP_ENTRY=%s\n' \
    "$DESKTOP_ENTRY"

printf 'LEGACY_WINE_DESKTOP_ARCHIVED=%s\n' \
    "$LEGACY_WINE_DESKTOP_ARCHIVED"

printf '\nINSTALLER_STAGE_3E_DESKTOP_INTEGRATION_PASS=True\n'

progress_stage_complete "Desktop integration"

# === MU_INSTALLER_STAGE_3E_DESKTOP_INTEGRATION_END ===

progress_assert_complete

# === MU_INSTALLER_FINAL_SUMMARY_BEGIN ===

log "Final installation validation"

[ -x "$RUNTIME/bin/wine" ] ||
    die "private Wine missing at final validation"

[ -x "$RUNTIME/bin/wineserver" ] ||
    die "private wineserver missing at final validation"

[ -d "$PREFIX" ] ||
    die "Wine prefix missing at final validation"

[ -f "$PREFIX/system.reg" ] ||
    die "system.reg missing at final validation"

[ -f "$MU_DIR/Mu.exe" ] ||
    die "Mu.exe missing at final validation"

[ -f "$MU_DIR/main.exe" ] ||
    die "main.exe missing at final validation"

[ -x "$LAUNCHER" ] ||
    die "MU launcher missing at final validation"

[ -f "$APPLICATION_ENTRY" ] ||
    die "application menu entry missing at final validation"

[ -x "$DESKTOP_ENTRY" ] ||
    die "desktop entry missing at final validation"

FINAL_WINE_VERSION="$(
    "$RUNTIME/bin/wine" --version
)"

[ "$FINAL_WINE_VERSION" = "wine-${WINE_VERSION}" ] ||
    die "unexpected final Wine version: $FINAL_WINE_VERSION"

printf 'FINAL_WINE_VERSION=%s\n' \
    "$FINAL_WINE_VERSION"

grep -Fi \
    'GGKernel64' \
    "$PREFIX/system.reg" \
    >/dev/null ||
    die "GGKernel64 compatibility service record missing"

FINAL_GG_DRIVER="$(
    find "$PREFIX/drive_c" \
        -type f \
        -iname 'GGKernel64.sys' \
        -print \
        -quit \
        2>/dev/null
)"

[ -z "$FINAL_GG_DRIVER" ] ||
    die "GGKernel64.sys exists before first user launch"

if [ -d "$MU_DIR/GameGuard" ]; then
    die "GameGuard directory exists before first user launch"
fi

printf 'FINAL_GGKERNEL64_SERVICE_RECORD_PRESENT=True\n'
printf 'FINAL_GGKERNEL64_SYS_PRESENT=False\n'
printf 'FINAL_GAMEGUARD_DIRECTORY_PRESENT=False\n'

log "Final launcher validation"

bash -n "$LAUNCHER" ||
    die "generated launcher syntax invalid"

grep -F \
    '"$RUNTIME/bin/wine"' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not pin private Wine"

grep -F \
    'WINESERVER="$RUNTIME/bin/wineserver"' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not pin private wineserver"

grep -F \
    './Mu.exe' \
    "$LAUNCHER" \
    >/dev/null ||
    die "launcher does not start Mu.exe"

printf 'FINAL_LAUNCHER_VALID=True\n'

printf '\n'
printf '============================================================\n'
printf ' MU Online Linux installation completed\n'
printf '============================================================\n'
printf '\n'

printf 'Base:     %s\n' "$BASE"
printf 'Runtime:  %s\n' "$RUNTIME"
printf 'Prefix:   %s\n' "$PREFIX"
printf 'MU:       %s\n' "$MU_DIR"
printf 'Launcher: %s\n' "$LAUNCHER"

printf '\n'
printf 'Start MU Online with:\n'
printf '  %s\n' "$LAUNCHER"
printf '\n'

printf 'INSTALLATION_COMPLETE=True\n'
printf 'PRIVATE_WINE_READY=True\n'
printf 'MU_INSTALLED=True\n'
printf 'GGKERNEL64_SERVICE_RECORD_SEEDED=True\n'
printf 'GGKERNEL64_DRIVER_COPIED=False\n'
printf 'GAMEGUARD_PATCHED=False\n'
printf 'GAME_STARTED=False\n'
printf 'LAUNCHER_READY=True\n'
printf 'DESKTOP_INTEGRATION_READY=True\n'

printf '\n'
printf 'NEXT_STEP=RUN_MU_LAUNCHER\n'

# === MU_INSTALLER_FINAL_SUMMARY_END ===
