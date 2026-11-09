# Changelog

All notable project changes intended for public releases are recorded here.

## 0.2.0 — CachyOS / Pacman support

### Added
- Experimental dependency preparation with the detected native Pacman,
  DNF or APT backend on unverified distributions after explicit `CONTINUE`.
  Unknown package managers, unavailable package roots and unsuccessful
  build audits fall back to guided manual dependency preparation. This
  does not expand the E2E-verified distribution list.
- CachyOS rolling-release discovery, native Pacman backend and 40-root
  dependency recipe including multilib and Vulkan headers.
- Automatic missing-package installation with the verified CachyOS recipe
  using Pacman's native transaction confirmation, and independent native,
  i386/x86_64 MinGW, graphics, GnuTLS and audio ABI validation.
- No hard-coded distribution allowlist: a Linux x86_64 system with an
  untested distribution ID is not rejected solely by its OS name.
  Instead, the installer classifies it as unverified and offers an
  experimental path after the user types `CONTINUE` (also accepts
  `continue`, case-insensitively). Build/toolchain/ABI verification is
  mandatory; missing or unsupported dependencies still block installation.
- A single case-insensitive `CONTINUE` consent for unverified distributions;
  no redundant package-manager or assisted-manual consent prompt.
- Assisted-manual dependency recheck after Enter when no verified
  automatic package recipe exists.
- Build/configure/runtime/prefix validation checkpoints and guarded
  --resume-from-prefix mode.
- --jobs N option for controlling Wine build parallelism on low-RAM VMs.

### Verified
- 2026-11-08: CachyOS x86_64 on a fresh KVM/QEMU VM; the installer
  detected five missing package roots, ran the native Pacman dependency
  transaction, and the user confirmed the full MU Online/game launch worked.
- Dependency-routing, platform-detection, consent and negative-safety tests
  passed on the test CachyOS VM after the final consent-flow changes.
- Patched Wine 11.6 source, full WoW64 build, private runtime installation,
  pristine prefix creation and nine matched build/runtime artifacts.

### Boundaries
- CachyOS is verified for the tested rolling-release environment, not
  every future rolling snapshot or GPU/driver combination.
- Generic Arch derivatives and Gentoo are not yet fully E2E verified.
- Previous v0.1.1 tag and archived release remain unchanged.
- Four Wine compatibility patches are unchanged.
- Proprietary MU Online and GameGuard binaries remain user-supplied.

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
