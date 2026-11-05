# Distribution Support

This document describes the Linux distribution and platform support implemented
by the current MU Online Linux installer.

The installer source is the implementation source of truth.

## Support model

The current installer recognizes three distribution IDs using two dependency backends:

- Fedora (ID=fedora) — DNF backend
- Nobara (ID=nobara) — DNF backend
- Ubuntu (ID=ubuntu) — APT backend

The installer does not currently contain dependency backends for Arch Linux,
openSUSE, Debian with `ID=debian`, or other distribution IDs.

A distribution being accepted by the installer is not the same as that exact
release having completed full end-to-end reference testing.

## Reference-tested systems

Full end-to-end installation and real game launch have been verified on:

| System | Architecture | Installer status | E2E status |
| --- | --- | --- | --- |
| Fedora 44 | x86_64 | Supported | Verified |
| Nobara Linux 44 | x86_64 | Fedora/DNF backend | Verified |
| Kubuntu 26.04.1, Ubuntu 26.04 base | x86_64 | Supported through `ID=ubuntu` | Verified |

The verified E2E path includes dependency installation, Wine build, private
runtime installation, fresh prefix creation, official MU installation,
GameGuard startup, login, character selection, world entry and working audio.

## Version handling

The installer reads `/etc/os-release` and dispatches by the `ID` field.

For Fedora:

```text
ID=fedora
```

is accepted.

Fedora 44 is the verified reference release.

If another Fedora release is detected, the installer prints a warning but does
not reject it solely because of the version number.

For Nobara:

    ID=nobara

Nobara 44 is E2E verified. It uses the existing Fedora/DNF backend.
Other Nobara releases receive a version warning.

For Ubuntu:

```text
ID=ubuntu
```

is accepted.

Ubuntu 26.04 is the current validated Ubuntu base.

If another Ubuntu release is detected, the installer prints a warning but does
not reject it solely because of the version number.

Ubuntu derivatives are accepted only when their `/etc/os-release` reports
`ID=ubuntu`.

The verified Kubuntu 26.04.1 installation follows this path because its base
reports Ubuntu 26.04 to the installer.

Other distribution IDs are rejected. The legacy fallback message reads:

```text
supported distributions are currently Fedora and Ubuntu
```

This message does not yet mention Nobara, although ID=nobara is accepted.
It will be revised in a future installer update.

## Operating system gate

The installer requires Linux.

The platform preflight checks:

```text
uname -s = Linux
```

A non-Linux system is rejected before distribution-specific dependency
handling begins.

## Architecture gate

The installer currently supports only:

```text
x86_64
```

The global platform preflight requires:

```text
uname -m = x86_64
```

The Ubuntu backend adds a second package-manager-specific architecture check:

```text
dpkg --print-architecture = amd64
```

Therefore ARM64/AArch64, 32-bit x86 and other host architectures are not
supported by the current installer.

The Wine runtime itself is built as a combined i386/x86_64 WoW64 runtime.
This does not mean the Linux host may be 32-bit; the host must still be
x86_64.

## Privilege model

The complete installer does not need to be started as root.

System-package operations are routed through an internal `run_root()` helper.

If the current user already has UID 0, the requested package-management
command is executed directly.

For an unprivileged user, the installer requires `sudo` when a system
dependency operation must be performed.

The project Wine runtime, Wine prefix, logs and generated launcher remain under
the selected user-owned project base rather than being installed as a system
Wine replacement.

## Dependency installation modes

By default the installer installs the dependency roots required by the
detected distribution backend.

The option:

```text
--skip-deps
```

suppresses package installation.

It does not suppress dependency validation.

When `--skip-deps` is used, the required commands, pkg-config modules and
multilib audio development files must already be available.

If required build commands are missing while `--skip-deps` is active, the
installer stops rather than attempting to continue with an incomplete build
environment.

## Fedora backend

For Fedora and Nobara the installer requires the `dnf` command.

Dependency installation is performed with:

```text
dnf install -y <package-list>
```

Fedora 44 is the full-E2E reference Fedora release.

Other Fedora and Nobara versions use the same DNF backend but receive
a warning when they differ from their verified release 44.

## Ubuntu backend

For Ubuntu the installer requires:

```text
apt-get
dpkg
```

The backend requires the native dpkg architecture to be:

```text
amd64
```

Because the Wine build and audio validation require both 64-bit and 32-bit
development components, the installer checks whether `i386` is enabled as a
foreign dpkg architecture.

If necessary it runs:

```text
dpkg --add-architecture i386
```

It then refreshes package metadata using:

```text
apt-get update
```

and installs the dependency roots using:

```text
apt-get install -y <package-list>
```

The apt operations run with:

```text
DEBIAN_FRONTEND=noninteractive
```

Ubuntu 26.04 is the current validated Ubuntu base.

Other Ubuntu versions enter the same backend but receive a warning that
Ubuntu 26.04 is the current validation target.


## Fedora dependency roots

The current Fedora backend installs the following package roots:

```text
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
```

Both x86_64 and i686 PulseAudio/ALSA development packages are intentional.
They support the combined i386/x86_64 Wine build.

## Ubuntu dependency roots

The current Ubuntu backend installs the following package roots:

```text
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
```

The explicit `:amd64` and `:i386` audio development packages are why the
Ubuntu backend enables the i386 foreign architecture before package
installation when required.

## Post-install command validation

After the dependency stage, the installer requires all of the following
commands to be available:

```text
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
```

A missing command at this stage is a hard failure.

This validation also applies after a normal dependency installation. The
installer therefore checks the resulting build environment rather than
assuming package-manager success is sufficient.

## Native development-library validation

The installer requires these pkg-config modules:

```text
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
```

Each module is tested with:

```text
pkg-config --exists <module>
```

A missing required module stops the installation before the Wine build.

## PulseAudio and ALSA multilib validation

In addition to the native pkg-config checks, the installer explicitly verifies
the expected 64-bit and 32-bit development metadata for both audio backends.

On Fedora it requires:

```text
/usr/lib64/pkgconfig/libpulse.pc
/usr/lib/pkgconfig/libpulse.pc
/usr/lib64/pkgconfig/alsa.pc
/usr/lib/pkgconfig/alsa.pc
```

On Ubuntu it requires:

```text
/usr/lib/x86_64-linux-gnu/pkgconfig/libpulse.pc
/usr/lib/i386-linux-gnu/pkgconfig/libpulse.pc
/usr/lib/x86_64-linux-gnu/pkgconfig/alsa.pc
/usr/lib/i386-linux-gnu/pkgconfig/alsa.pc
```

Every listed file must exist.

This is a deliberate multilib gate. The installer does not continue with only
the host-architecture audio development files present.

## Wine audio configuration validation

After Wine configure, the installer performs additional checks to ensure the
audio support was actually enabled by Wine.

It requires non-empty configure results for:

```text
PULSE_LIBS
ALSA_LIBS
```

It also rejects a configuration in which either:

```text
winepulse.drv
winealsa.drv
```

is disabled.

Later build and runtime validation requires the resulting private runtime to
contain:

```text
lib/wine/x86_64-unix/winepulse.so
lib/wine/x86_64-unix/winealsa.so
```

The reference Fedora 44 and Kubuntu 26.04.1 E2E runs reached the MU world with
working game audio.

## GnuTLS and Schannel validation

GnuTLS development support is mandatory for the current Wine build.

The dependency roots providing it are:

```text
Fedora: gnutls-devel
Ubuntu: libgnutls28-dev
```

After Wine configure, the installer inspects the configure result and requires
successful detection of:

```text
gnutls/gnutls.h
gnutls_cipher_init
```

It also rejects a configure result containing:

```text
no schannel support
```

A valid configuration therefore reaches the installer markers corresponding
to:

```text
GNUTLS_HEADER_DETECTED=True
GNUTLS_CIPHER_DETECTED=True
SCHANNEL_ENABLED=True
```

This check exists because Wine can otherwise build successfully while missing
Schannel functionality needed by the MU client.

## `--skip-deps` expectations

`--skip-deps` is intended for an already-prepared build environment.

It skips:

```text
dnf install
```

or the Ubuntu package-management sequence:

```text
dpkg --add-architecture i386
apt-get update
apt-get install
```

as applicable.

It does not bypass:

```text
required command validation
pkg-config module validation
PulseAudio/ALSA multilib validation
Wine configure validation
GnuTLS/Schannel validation
Wine audio validation
```

Therefore `--skip-deps` cannot be used to force an unsupported or incomplete
build environment through the installer.


## Support-status terminology

The project uses the following meanings when describing distribution support.

### E2E verified

A distribution release is **E2E verified** only after the complete real
installation and launch path has been exercised on that release.

The qualification must cover the relevant path from a clean test environment
through actual gameplay.

For the current reference systems this includes:

```text
platform preflight
  -> dependency installation
  -> dependency validation
  -> Wine source download and SHA256 verification
  -> Wine patch verification and application
  -> Wine configure
  -> GnuTLS / Schannel validation
  -> PulseAudio / ALSA validation
  -> Wine build
  -> private Wine runtime installation
  -> fresh Wine prefix creation
  -> official MU Online installation
  -> GameGuard service-record configuration
  -> desktop integration
  -> desktop launch
  -> GameGuard startup
  -> MU login
  -> character selection
  -> world entry
  -> working audio
```

An installer backend merely accepting a distribution is not sufficient for
E2E-verified status.

### Supported by the current backend

A system is **supported by the current backend** when its `/etc/os-release`
selects one of the implemented dependency backends and it passes the current
platform and dependency gates.

At present these distribution IDs select implemented backends:

```text
fedora
nobara
ubuntu
```

This means an untested Fedora, Nobara or Ubuntu release may be accepted
without having E2E-verified status.

### Accepted with version warning

A Fedora or Nobara release other than 44, or an Ubuntu release other
than 26.04, enters its dependency backend with a version warning.

The warning means:

- the dependency backend is available
- the installer is willing to attempt the current workflow
- that exact operating-system release is not the current reference-tested
  release

The warning must not be interpreted as confirmation that the complete MU and
GameGuard lifecycle has been verified on that release.

### Unsupported

A platform is currently unsupported when the installer has no implemented
path for it.

Examples include:

- non-Linux hosts
- non-x86_64 hosts
- distribution IDs other than `fedora`, `nobara` and `ubuntu`
- Ubuntu installations whose native dpkg architecture is not `amd64`

Using `--skip-deps` does not change these platform or distribution gates.

## Known support boundaries

The current support layer is intentionally narrow.

It does not currently provide:

```text
Arch Linux / pacman backend
openSUSE / zypper backend
Debian ID backend
generic package-manager-independent dependency resolution
ARM64 host support
32-bit Linux host support
```

Support for another Linux distribution requires more than translating package
names.

The resulting Wine build must still satisfy the same functional requirements,
including:

```text
combined i386/x86_64 WoW64 build
MinGW PE toolchain
GnuTLS / Schannel support
PulseAudio support
ALSA support
32-bit and 64-bit audio development metadata
required patched Wine artifacts
private runtime validation
GameGuard compatibility path
```

## Ubuntu derivatives

The installer dispatches by the `ID` value from `/etc/os-release`.

A desktop environment or distribution branding does not by itself create a
new backend.

For example, the tested Kubuntu 26.04.1 environment follows the Ubuntu backend
because the system identifies itself to the installer with:

```text
ID=ubuntu
VERSION_ID=26.04
```

A derivative reporting a different `ID` does not automatically inherit Ubuntu
backend support.

## Qualifying a new distribution release

Before adding another release to the reference-tested matrix, test it from a
clean or otherwise precisely documented baseline.

At minimum, record and verify:

```text
distribution identity and version
host architecture
installer SHA256
README/documentation state if relevant
dependency installation result
required command validation
pkg-config validation
audio multilib validation
Wine source SHA256
patch SHA256 validation
Wine configure result
GnuTLS / Schannel result
Wine audio result
Wine build result
private runtime validation
fresh prefix result
official MU installation result
GameGuard service-record result
desktop integration result
real desktop launch result
GameGuard runtime result
login result
character-selection result
world-entry result
audio result
```

The test should use the normal installer dependency backend unless the purpose
of the test is explicitly to validate `--skip-deps`.

A successful Wine build alone is not sufficient to qualify a distribution
release.

A successful MU installer window alone is also not sufficient.

The real GameGuard and game lifecycle must complete.

## Qualification provenance

Each reference test should record the exact installer SHA256 used for the
test.

If a later installer state differs from the full-E2E-tested state, the
difference must be documented rather than silently treating the new SHA as if
it had completed the same E2E run.

For the v0.1.0 release (historical):

```text
Full-E2E-tested base installer:
e2c82048dfd6d5a41bcb5620056a91861bcba0548e0c6d2d5c5230ec05987b7b

v0.1.0 release installer:
2daa0ceafe55a12b9c78679505ce3f4dff41ebc8824ad83bca44dca58619a984
```

The v0.1.0 installer differs from that full-E2E-tested base only by the
Stage 2E private-runtime-install heartbeat.

That change received a separate exact scope audit and interactive/non-
interactive runtime tests, but that v0.1.0 SHA was not subjected to another
complete Wine-build and game E2E run.

This distinction should remain visible in release and test documentation.

## v0.1.1 Nobara qualification

Nobara Linux 44 x86_64 completed a full installation and real
MU Online gameplay test using the Fedora/DNF dependency backend.

E2E-tested installer SHA256:

    34c011d75678e9007336e65a7f6058561dbff682f50b4f9f58686cd7494fdecc

Wine 11.6, the four compatibility patches and GameGuard handling
were not modified for v0.1.1.

## Adding a new distribution family

Adding a new distribution family requires an explicit installer backend.

At minimum this requires:

```text
/etc/os-release ID handling
package-manager command validation
dependency-root mapping
multilib architecture handling
MinGW toolchain mapping
native development-library mapping
PulseAudio / ALSA multilib mapping
clean-system dependency test
Wine build test
full MU / GameGuard E2E test
```

A new backend should fail closed when required dependencies or architecture
assumptions are not satisfied.

It should not weaken existing Wine, GameGuard, networking or audio validation
merely to make a distribution pass installation.

## Current reference matrix

| Distribution | Release | Host architecture | Backend | Full E2E |
| --- | --- | --- | --- | --- |
| Fedora | 44 | x86_64 | Fedora / dnf | Yes |
| Nobara Linux | 44 | x86_64 | Fedora / dnf | Yes |
| Kubuntu | 26.04.1 | x86_64 | Ubuntu / apt | Yes |

The Kubuntu result represents the tested Ubuntu 26.04-based path currently used
as the Ubuntu-family reference.

The verified matrix is limited to the three tested releases above.

