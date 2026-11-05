#!/usr/bin/env bash
# Phase 1: read-only OS and native package-manager discovery.
# Source this module; it never installs packages or modifies the host.

mu_like_has() {
    local needle="$1"
    case " $MU_DISTRO_LIKE " in
        *" $needle "*) return 0 ;;
        *) return 1 ;;
    esac
}

mu_detect_platform() {
    local release_file="${1:-/etc/os-release}"
    local os_data
    local -a fields=()

    [[ -f "$release_file" && -r "$release_file" ]] || {
        printf 'ERROR: cannot read OS release file: %s\n' "$release_file" >&2
        return 1
    }

    os_data="$(
        set +u
        # os-release is a trusted local OS configuration file.
        . "$release_file" || exit 1
        printf '%s\n' "$ID" "$ID_LIKE" "$VERSION_ID"
    )" || return 1
    mapfile -t fields <<< "$os_data"

    MU_DISTRO_ID="${fields[0],,}"
    MU_DISTRO_LIKE="${fields[1],,}"
    MU_DISTRO_VERSION="${fields[2]}"
    MU_HOST_ARCH="$(uname -m)"
    MU_DISTRO_STATUS="unverified"
    MU_PKG_CANDIDATE="none"
    MU_PKG_BACKEND="manual"
    MU_PKG_RECIPE="unavailable"
    MU_BUILD_ENV_STATUS="not_checked"

    case "$MU_DISTRO_ID:$MU_DISTRO_VERSION" in
        fedora:44|nobara:44|ubuntu:26.04)
            MU_DISTRO_STATUS="verified" ;;
    esac

    case "$MU_DISTRO_ID" in
        fedora|nobara) MU_PKG_CANDIDATE="dnf" ;;
        ubuntu) MU_PKG_CANDIDATE="apt" ;;
        arch|cachyos) MU_PKG_CANDIDATE="pacman" ;;
        *)
            if mu_like_has fedora; then
                MU_PKG_CANDIDATE="dnf"
            elif mu_like_has ubuntu || mu_like_has debian; then
                MU_PKG_CANDIDATE="apt"
            elif mu_like_has arch; then
                MU_PKG_CANDIDATE="pacman"
            fi
            ;;
    esac

    # Three independent signals: lineage, executable, native package database.
    # A secondary package manager installed on an unrelated distro is rejected.
    case "$MU_PKG_CANDIDATE" in
        dnf)
            if command -v dnf >/dev/null 2>&1 &&
               command -v rpm >/dev/null 2>&1 &&
               rpm --eval '%{_dbpath}' >/dev/null 2>&1; then
                MU_PKG_BACKEND="dnf"
            fi ;;
        apt)
            if command -v apt-get >/dev/null 2>&1 &&
               command -v dpkg >/dev/null 2>&1 &&
               [[ -r /etc/debian_version ]] &&
               dpkg --print-architecture >/dev/null 2>&1; then
                MU_PKG_BACKEND="apt"
            fi ;;
        pacman)
            if command -v pacman >/dev/null 2>&1 &&
               [[ -r /etc/pacman.conf ]] &&
               pacman -Q pacman >/dev/null 2>&1; then
                MU_PKG_BACKEND="pacman"
            fi ;;
    esac

    # Package recipes are not inferred from ID_LIKE.
    # Arch/CachyOS recipe is intentionally pending implementation.
    case "$MU_DISTRO_ID:$MU_PKG_BACKEND" in
        fedora:dnf|nobara:dnf) MU_PKG_RECIPE="fedora-v011" ;;
        ubuntu:apt) MU_PKG_RECIPE="ubuntu-v011" ;;
    esac
}

mu_platform_report() {
    printf 'DISTRIBUTION_ID=%s\n' "$MU_DISTRO_ID"
    printf 'DISTRIBUTION_LIKE=%s\n' "$MU_DISTRO_LIKE"
    printf 'DISTRIBUTION_VERSION=%s\n' "$MU_DISTRO_VERSION"
    printf 'ARCHITECTURE=%s\n' "$MU_HOST_ARCH"
    printf 'DISTRIBUTION_STATUS=%s\n' "$MU_DISTRO_STATUS"
    printf 'PACKAGE_MANAGER_CANDIDATE=%s\n' "$MU_PKG_CANDIDATE"
    printf 'PACKAGE_MANAGER_BACKEND=%s\n' "$MU_PKG_BACKEND"
    printf 'PACKAGE_RECIPE=%s\n' "$MU_PKG_RECIPE"
    printf 'BUILD_ENV_STATUS=%s\n' "$MU_BUILD_ENV_STATUS"
}
