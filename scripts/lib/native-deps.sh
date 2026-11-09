#!/usr/bin/env bash
# Shared package-name recipes for DNF/APT (verified references and experimental native backends).
# Sourcing this module only defines data; it does not run package transactions.

FEDORA_PACKAGES=(
    gcc
    gcc-c++
    make
    bison
    flex

    mingw32-gcc
    mingw32-binutils
    mingw64-gcc
    mingw64-binutils

    gettext

    curl
    file
    patch
    python3
    tar
    xz
    pkgconf-pkg-config

    freetype-devel
    fontconfig-devel
    gnutls-devel

    libX11-devel
    libXext-devel
    libXcursor-devel
    libXi-devel
    libXrandr-devel
    libXrender-devel
    libXinerama-devel
    libXcomposite-devel
    libXfixes-devel
    libXdamage-devel
    libXxf86vm-devel
    libxcb-devel
    libxkbcommon-devel

    wayland-devel

    mesa-libEGL-devel
    mesa-libGL-devel
    mesa-libgbm-devel
    vulkan-loader-devel

    pulseaudio-libs-devel.x86_64
    pulseaudio-libs-devel.i686
    alsa-lib-devel.x86_64
    alsa-lib-devel.i686

    coreutils
    diffutils
    findutils
    grep
    sed
    gawk
    perl
)

UBUNTU_PACKAGES=(
    build-essential
    gcc
    g++
    make
    bison
    flex

    gcc-mingw-w64-i686-posix
    binutils-mingw-w64-i686
    gcc-mingw-w64-x86-64-posix
    binutils-mingw-w64-x86-64

    gettext

    curl
    file
    patch
    python3
    tar
    xz-utils
    pkg-config

    libfreetype-dev
    libfontconfig1-dev
    libgnutls28-dev

    libx11-dev
    libxext-dev
    libxcursor-dev
    libxi-dev
    libxrandr-dev
    libxrender-dev
    libxinerama-dev
    libxcomposite-dev
    libxfixes-dev
    libxdamage-dev
    libxxf86vm-dev
    libxcb1-dev
    libxkbcommon-dev

    libwayland-dev

    libegl-dev
    libgl-dev
    libgbm-dev
    libvulkan-dev

    libpulse-dev:amd64
    libpulse-dev:i386
    libasound2-dev:amd64
    libasound2-dev:i386

    coreutils
    diffutils
    findutils
    grep
    sed
    gawk
    perl
)
