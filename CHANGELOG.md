# Changelog

All notable project changes intended for public releases are recorded here.

## 0.1.1 — Nobara Linux 44 support

### Added
- Nobara Linux detection (ID=nobara).
- Fedora/DNF dependency backend for Nobara.
- Version warning for Nobara releases other than 44.

### Verified
- Nobara Linux 44 x86_64.
- Automatic dependency installation.
- Private patched Wine 11.6 build and installation.
- MU Online installation and successful gameplay.

### Compatibility
- Four Wine patches unchanged.
- Fedora and Ubuntu backends unchanged.
- v0.1.0 remains available unchanged.

### E2E installer SHA256
34c011d75678e9007336e65a7f6058561dbff682f50b4f9f58686cd7494fdecc

## 0.1.0

Initial public release.

### Added

- automated MU Online Linux installer
- tagged bootstrap entry point for versioned releases
- deterministic release archive and SHA256 checksum publication
- private Wine 11.6 build and runtime
- isolated Wine prefix
- Fedora and Ubuntu-family dependency backends
- Wine source download and SHA256 validation
- four pinned Wine compatibility patches
- GnuTLS / Schannel configure validation
- foreground Wine build with progress heartbeat
- private-runtime installation heartbeat
- official user-supplied MU Online installer flow
- GGKernel64 Wine SCM service-record preparation
- private MU launcher
- managed desktop and application-menu integration
- failure-state preservation and diagnostic logging
- production documentation for architecture, Wine building, patches,
  GameGuard compatibility, distribution support and troubleshooting

### Verified environments

Full end-to-end installation and real game launch have been verified on:

- Fedora 44 x86_64
- Kubuntu 26.04.1 x86_64 using the Ubuntu 26.04 backend

The verified path reached the MU Online world with GameGuard enabled and
working through the project's private Wine compatibility runtime.

### Distribution boundaries

The release does not include:

- the proprietary MU Online installer
- Mu.exe
- main.exe
- GameGuard binaries
- GGKernel64.sys
- a prebuilt Wine runtime

The user supplies the official MU Online installer separately.

### Licensing

Original project code and documentation use the MIT License.

Wine-derived patch material is distributed under LGPL-2.1-or-later.
