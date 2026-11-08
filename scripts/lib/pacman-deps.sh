#!/usr/bin/env bash
# Experimental Arch-style pacman dependency recipe for MU Online Linux v0.2.0.
# Intended for sourcing; only checks packages when mu_pacman_audit is called.

mu_pacman_roots() {
    MU_PACMAN_PACKAGES=(
        base-devel bison flex gettext curl file patch python tar xz pkgconf
        mingw-w64-gcc mingw-w64-binutils
        freetype2 fontconfig gnutls
        libx11 libxext libxcursor libxi libxrandr libxrender libxinerama
        libxcomposite libxfixes libxdamage libxxf86vm libxcb libxkbcommon
        wayland mesa libglvnd vulkan-icd-loader vulkan-headers
        libpulse alsa-lib lib32-libpulse lib32-alsa-lib
        lib32-glibc lib32-gcc-libs
    )
}

mu_pacman_audit() {
    local pkg
    MU_PACMAN_INSTALLED=0
    MU_PACMAN_MISSING=()
    MU_PACMAN_UNAVAILABLE=()

    for pkg in "${MU_PACMAN_PACKAGES[@]}"; do
        if pacman -Qq "$pkg" >/dev/null 2>&1; then
            printf 'INSTALLED   %s\n' "$pkg"
            ((MU_PACMAN_INSTALLED+=1))
        elif pacman -Si "$pkg" >/dev/null 2>&1; then
            printf 'AVAILABLE   %s\n' "$pkg"
            MU_PACMAN_MISSING+=("$pkg")
        else
            printf 'NOT_FOUND   %s\n' "$pkg"
            MU_PACMAN_UNAVAILABLE+=("$pkg")
        fi
    done

    printf '\nPACMAN_ROOTS_TOTAL=%d\n' "${#MU_PACMAN_PACKAGES[@]}"
    printf 'PACMAN_ROOTS_INSTALLED=%d\n' "$MU_PACMAN_INSTALLED"
    printf 'PACMAN_ROOTS_AVAILABLE=%d\n' "${#MU_PACMAN_MISSING[@]}"
    printf 'PACMAN_ROOTS_UNAVAILABLE=%d\n' "${#MU_PACMAN_UNAVAILABLE[@]}"

    if (( ${#MU_PACMAN_UNAVAILABLE[@]} )); then
        printf 'PACMAN_RECIPE_STATUS=unavailable\n'
        return 1
    fi

    printf 'PACMAN_RECIPE_STATUS=available\n'
    return 0
}
