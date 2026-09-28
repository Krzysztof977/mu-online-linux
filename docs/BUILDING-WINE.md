# Building the Private Wine Runtime

This document describes how the project acquires, patches, configures, builds
and installs its private Wine runtime.

The installer is the canonical implementation.

The commands and checks described here explain that implementation rather than
providing an independent second build system.

## Build model

MU Online is not run with the distribution Wine package.

The project builds a private Wine runtime from a pinned upstream source archive
and four repository patches.

The high-level sequence is:

```text
verified Wine source archive
  -> pristine source tree
  -> verified patch sequence
  -> configured WoW64 build tree
  -> compiled build artifacts
  -> private Wine runtime
  -> Wine prefix creation
  -> MU installation
```

This document covers the Wine portion through private-runtime installation.

Prefix creation happens later.

## Pinned Wine source

The current Wine version is:

```text
11.6
```

The source archive name is:

```text
wine-11.6.tar.xz
```

The installer constructs the source URL from:

```text
https://dl.winehq.org/wine/source/11.x/
```

and the archive name.

The resulting source is:

```text
https://dl.winehq.org/wine/source/11.x/wine-11.6.tar.xz
```

The expected archive SHA256 is:

```text
d49d166975478f609e6a9cdbda0a07c65a3b795e061fc454d3f1034c828d19e0
```

The checksum is an integrity requirement.

The archive is not accepted merely because it has the expected filename.

## Patch inputs

The source tree is modified by these repository patches:

```text
0001-ntdll-ntloaddriver-scm.patch
0002-ntdll-wow64-stack-semantics.patch
0003-kernelbase-urlescape-sentinel.patch
0004-ntoskrnl-gameguard-compat.patch
```

Each patch also has a pinned SHA256 digest.

The exact patch hashes and source-level behavior are documented in:

```text
PATCHES.md
```

Patch integrity is checked before the source-build stages proceed.

## Workspace layout

The relevant installer paths are based below the selected installation base.

The patched source tree is:

```text
<work>/wine-11.6-patched
```

The configured build tree is:

```text
<work>/build-wow64
```

The final private runtime is:

```text
<base>/runtime/wine-11.6-mu
```

Logs are stored below:

```text
<base>/logs
```

The source tree, build tree and installed runtime are deliberately separate.

This allows the installer to validate each transition independently.

## Stage 2B: Wine source and patches

Stage 2B is responsible for:

```text
source acquisition
archive integrity
archive-layout validation
source extraction
patch application
patch-state verification
patched-source structural validation
```

Its success marker is:

```text
INSTALLER_STAGE_2B_SOURCE_PATCH_PASS=True
```

## Cached source archive handling

If the Wine archive is already present, the installer verifies its SHA256.

A valid cached archive is reused.

A cached archive with the wrong checksum is not silently overwritten or used.

It is moved aside with a timestamped bad-archive name.

This preserves evidence of the invalid input while preventing it from entering
the build.

## Download handling

If a valid archive is not available, the installer downloads to a temporary:

```text
.part.<pid>
```

file.

The download uses `curl` with:

```text
--fail
--location
--retry 3
--retry-delay 2
```

The temporary download is SHA256-verified before it is moved to the normal
archive path.

If the downloaded file has the wrong checksum, it is preserved with a
timestamped bad-SHA name and the installer stops.

The final archive is also verified again before extraction.

## Archive-layout validation

Before extraction, the installer examines the tar archive.

It requires exactly one entry matching:

```text
wine-11.6/configure
```

An unexpected archive layout is treated as an error.

This prevents the build process from relying only on the archive filename or
checksum while assuming an unchecked internal structure.

## Source extraction

For a fresh source workspace, extraction happens first in a temporary
directory.

The installer requires the extracted:

```text
wine-11.6/
```

directory and its executable:

```text
configure
```

script to exist.

Only after those checks is the extracted tree moved into the persistent patched
source path.

The temporary extraction directory is then removed.

## Existing source workspace

An existing source workspace is not automatically discarded.

Instead, the installer validates its patch state before reuse.

This makes interrupted or repeated installations recoverable without assuming
that an existing source tree is correct.

## Patch application state

For each patch, the installer first performs a forward dry run using:

```text
patch --dry-run --forward --batch -p1
```

If that succeeds, the patch is applied with:

```text
patch --forward --batch -p1
```

If the forward dry run does not succeed, the installer performs a reverse dry
run using:

```text
patch --dry-run --reverse --batch -p1
```

A successful reverse dry run means the patch is already applied.

If neither state is valid, the installer stops with a source-tree compatibility
error.

## Final patch verification

After processing all four patches, the complete sequence is verified again.

Every patch must pass a reverse dry run.

That proves the final source tree contains each expected patch according to
`patch`'s view of the source.

The installer does not accept a partially patched source tree.

## Patched-source structural validation

The installer also requires the expected modified source files to exist.

These include:

```text
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
```

It additionally checks for representative compatibility markers including:

```text
NtLoadDriver
KeGetCurrentIrql
```

This structural validation complements the patch-state checks.

## Stage 2C: configure Wine

Stage 2C configures the patched source for the project's WoW64 build.

Its success marker is:

```text
INSTALLER_STAGE_2C_CONFIGURE_PASS=True
```

The configure log is:

```text
<base>/logs/wine-11.6-configure.log
```

## Configure command

For a fresh build directory, the effective configure operation is:

```text
<patched-source>/configure \
    --prefix=<base>/runtime/wine-11.6-mu \
    --enable-archs=i386,x86_64
```

The current project therefore builds both PE architectures required by this
WoW64 configuration:

```text
i386
x86_64
```

## Private prefix target

The configure `--prefix` is the project's private runtime directory.

It is not a system path such as:

```text
/usr
/usr/local
```

The Wine build therefore installs into the MU-specific runtime tree rather than
replacing the host distribution's Wine installation.

## Existing build directory

A missing build directory is created and configured.

An existing build directory may be reused only if it contains both:

```text
Makefile
config.status
```

If the directory exists but does not represent a complete configured build, the
installer stops.

## Configure-argument validation

After configuration, the installer verifies that `config.status` contains the
expected arguments:

```text
--prefix=<private-runtime> --enable-archs=i386,x86_64
```

This prevents an unrelated or differently configured Wine build tree from
being reused accidentally.

## PE architecture validation

The installer reads the generated Makefile and requires:

```text
PE_ARCHS=i386 x86_64
```

The success marker is:

```text
WOW64_ARCHS_OK=True
```

## Audio configuration validation

The configured Wine build must contain working audio development-library
configuration.

The installer reads:

```text
PULSE_CFLAGS
PULSE_LIBS
ALSA_LIBS
```

from the generated Makefile.

Both:

```text
PULSE_LIBS
ALSA_LIBS
```

must be non-empty.

It also checks `DISABLED_SUBDIRS`.

Neither:

```text
winepulse.drv
winealsa.drv
```

may be disabled.

Successful validation produces:

```text
PULSE_LIBS_PRESENT=True
ALSA_LIBS_PRESENT=True
WINEPULSE_DISABLED=False
WINEALSA_DISABLED=False
AUDIO_DRIVERS_ENABLED=True
```

## GnuTLS and Schannel validation

GnuTLS is a required part of the verified Wine configuration.

The configure log must contain:

```text
checking for gnutls/gnutls.h... yes
checking for gnutls_cipher_init... yes
```

and must not contain:

```text
no schannel support
```

Successful validation produces:

```text
GNUTLS_HEADER_DETECTED=True
GNUTLS_CIPHER_DETECTED=True
SCHANNEL_ENABLED=True
```

This check exists because a Wine build can otherwise complete while lacking the
Schannel functionality required by the verified MU runtime path.

Distribution-specific GnuTLS development packages are documented in:

```text
DISTRO-SUPPORT.md
```

## Patched-source validation after configure

The installer checks again that representative patched-source markers remain
present after configuration.

The current markers are:

```text
NtLoadDriver
KeGetCurrentIrql
```

A configure operation must not replace or invalidate the expected patched
source state.

## Runtime isolation during configure

The private runtime must not exist before compilation.

It must also remain absent after configure.

Stage 2C therefore separates:

```text
source configuration
```

from:

```text
runtime installation
```

## Stage 2D: build Wine

Stage 2D compiles the configured Wine tree.

Its success marker is:

```text
INSTALLER_STAGE_2D_BUILD_PASS=True
```

The build log is:

```text
<base>/logs/wine-11.6-build.log
```

## Parallel build jobs

The installer obtains the job count from:

```text
nproc
```

with a fallback of:

```text
1
```

The result must be a positive integer.

The build command is effectively:

```text
make -C <build-tree> -j<JOBS>
```

## Build execution model

The actual `make` process runs in the foreground from the installer's control
flow.

A separate heartbeat process reports progress information.

The heartbeat does not replace the build process and does not define build
success.

The authoritative build result is the exit status of:

```text
make
```

## No artificial build timeout

The build stage does not terminate compilation because an arbitrary amount of
time has elapsed.

Compilation time depends strongly on:

```text
CPU performance
available cores
memory
storage
host load
virtual-machine resources
```

Long build time, slow scrolling or periods with little visible terminal output
are not by themselves build failures.

## Build heartbeat

During compilation the installer records the build start time and runs its
build heartbeat alongside `make`.

The heartbeat provides visibility into a long-running build.

Once `make` exits, only the heartbeat process is stopped and reaped.

The build result remains the foreground `make` return code.

## Build failure handling

If `make` returns non-zero, the installer prints the final:

```text
120
```

lines of the build log.

It also extracts a bounded set of error-like lines matching conditions such as:

```text
error:
fatal error:
undefined reference
collect2: error
make: ***
```

The complete build log remains available for deeper diagnosis.

The installer then stops rather than continuing to runtime installation.

## Required build artifacts

A successful build must produce:

```text
dlls/ntdll/ntdll.so
dlls/ntdll/i386-windows/ntdll.dll
dlls/ntdll/x86_64-windows/ntdll.dll

dlls/kernelbase/i386-windows/kernelbase.dll
dlls/kernelbase/x86_64-windows/kernelbase.dll

dlls/ntoskrnl.exe/i386-windows/ntoskrnl.exe
dlls/ntoskrnl.exe/x86_64-windows/ntoskrnl.exe

dlls/winepulse.drv/winepulse.so
dlls/winealsa.drv/winealsa.so
```

Missing required output is a hard failure.

## Build architecture validation

The installer uses `file` to validate representative output architectures.

The expected forms include:

```text
i386 ntdll.dll:
  PE32 / Intel i386

x86_64 ntdll.dll:
  PE32+ / x86-64

x86_64 ntoskrnl.exe:
  PE32+ / x86-64

winepulse.so:
  ELF 64-bit / x86-64

winealsa.so:
  ELF 64-bit / x86-64
```

Successful validation produces:

```text
BUILD_ARCHITECTURES_OK=True
```

## Build artifact hashes

After validation, the installer records SHA256 hashes for the required
compatibility and audio artifacts.

These recorded hashes describe the artifacts produced by that build.

The source archive and repository patch hashes are the pinned build inputs.

## Runtime and prefix boundary after build

Stage 2D is compilation only.

Before Stage 2E:

```text
make install has not run
private runtime does not exist
Wine prefix does not exist
```

The installer explicitly reports:

```text
MAKE_INSTALL_EXECUTED=False
RUNTIME_CREATED=False
PREFIX_CREATED=False
```

This separation makes it possible to distinguish a compilation failure from an
installation or prefix-initialization failure.

## Stage 2E: install private Wine runtime

Stage 2E installs the completed build into the private runtime.

Its success marker is:

```text
INSTALLER_STAGE_2E_RUNTIME_INSTALL_PASS=True
```

The install log is:

```text
<base>/logs/wine-11.6-install.log
```

## Runtime installation command

The actual install operation is:

```text
make -C <build-tree> install
```

The command runs in the foreground.

As with the build stage, a separate heartbeat reports progress without replacing
the real process.

## Runtime-install preconditions

Before `make install`, the installer requires:

```text
build directory exists
build Makefile exists
private runtime does not exist
Wine prefix does not exist
```

An already existing runtime is not silently overwritten.

## Install heartbeat

The installer records installation start time and launches the private-runtime
installation heartbeat.

The heartbeat is informational.

When `make install` exits, the installer stops and waits only for the heartbeat
process.

The return code from `make install` determines success or failure.

## Install failure handling

If runtime installation fails, the installer prints the final:

```text
120
```

lines of the install log.

If the failed install created a partial runtime directory, that directory is
preserved by moving it to a timestamped path of the form:

```text
wine-11.6-mu.failed-install.<timestamp>
```

The partial result is therefore not silently reused as a valid runtime.

## Required runtime executables

After successful installation, these executables must exist and be executable:

```text
<runtime>/bin/wine
<runtime>/bin/wineboot
<runtime>/bin/wineserver
```

## Runtime version validation

The private Wine binary is executed with:

```text
wine --version
```

The output must be exactly:

```text
wine-11.6
```

The success marker is:

```text
PRIVATE_WINE_VERSION_OK=True
```

## Required installed runtime files

The installed runtime must contain:

```text
lib/wine/x86_64-unix/ntdll.so

lib/wine/i386-windows/ntdll.dll
lib/wine/x86_64-windows/ntdll.dll

lib/wine/i386-windows/kernelbase.dll
lib/wine/x86_64-windows/kernelbase.dll

lib/wine/i386-windows/ntoskrnl.exe
lib/wine/x86_64-windows/ntoskrnl.exe

lib/wine/x86_64-unix/winepulse.so
lib/wine/x86_64-unix/winealsa.so
```

Missing files make the runtime invalid.

## Build-to-runtime identity check

The installer compares the important build artifacts with their installed
runtime copies using:

```text
cmp -s
```

The checked pairs cover:

```text
ntdll.so
i386 ntdll.dll
x86_64 ntdll.dll
i386 kernelbase.dll
x86_64 kernelbase.dll
i386 ntoskrnl.exe
x86_64 ntoskrnl.exe
winepulse.so
winealsa.so
```

Every checked installed file must be byte-identical to its corresponding build
artifact.

Successful comparison produces:

```text
BUILD_RUNTIME_ARTIFACTS_IDENTICAL=True
```

## Installed architecture inspection

After the identity checks, the installer runs `file` over representative
installed runtime components.

This records the installed architecture state for:

```text
i386 Windows binaries
x86_64 Windows binaries
x86_64 Unix Wine components
audio drivers
```

## Runtime artifact hashes

The installer records SHA256 hashes for the installed private Wine binary,
wineserver and important compatibility/runtime files.

This provides a concrete diagnostic record of the runtime produced by the
current build.

## Prefix remains separate

Installing the private Wine runtime does not initialize the Wine prefix.

At the end of Stage 2E the prefix must still not exist.

The installer reports:

```text
PREFIX_CREATED=False
```

Prefix creation is handled by a later installation stage.

## Build logs

The Wine stages use these primary logs:

```text
<base>/logs/wine-11.6-configure.log
<base>/logs/wine-11.6-build.log
<base>/logs/wine-11.6-install.log
```

When investigating a failure, use the complete log corresponding to the failed
stage.

Terminal tails are diagnostic summaries, not substitutes for the full logs.

For operational diagnosis, see:

```text
TROUBLESHOOTING.md
```

## Reuse and restart behavior

The build pipeline is designed to distinguish valid reusable state from
ambiguous partial state.

Examples include:

```text
verified cached source archive:
  reusable

existing patched source:
  reusable only after patch-state validation

existing configured build tree:
  reusable only with Makefile and config.status and validation

partial failed runtime:
  preserved separately, not accepted as the runtime

unexpected existing runtime before its stage:
  hard failure
```

This is preferable to deleting build state automatically after every
interruption.

## Manual developer reproduction

The installer's canonical configuration can be summarized as:

```text
obtain verified Wine 11.6 source
apply the four verified repository patches
create a separate build directory
run configure with:
  --prefix=<private-runtime>
  --enable-archs=i386,x86_64
run:
  make -j<JOBS>
run:
  make install
perform the same post-build and post-install validation
```

A manual build that merely compiles successfully is not equivalent to the
verified installer result unless the integrity and runtime checks also pass.

## System dependencies

This document intentionally does not duplicate the complete Fedora and Ubuntu
package arrays.

Those are maintained in:

```text
DISTRO-SUPPORT.md
```

The important build-time capabilities include:

```text
native C/C++ compiler
MinGW i686 and x86_64 toolchains
bison
flex
gettext
pkg-config
GnuTLS development files
PulseAudio development files
ALSA development files
X11 / Wayland development files
EGL / GL / GBM / Vulkan development files
```

The installer performs its own dependency and native-library validation before
the Wine source-build stages.

## Security and isolation boundaries

The private-runtime design intentionally avoids modifying the host's normal Wine
installation.

The project runtime is kept below:

```text
<base>/runtime/
```

and subsequent MU launcher operations use that private runtime.

The Wine patches affect only the project-built Wine source and resulting
private runtime.

They do not patch:

```text
Mu.exe
main.exe
GameGuard binaries
```

and the project does not supply:

```text
GGKernel64.sys
```

The GameGuard-specific compatibility model is documented in:

```text
GAMEGUARD-COMPAT.md
```

## Reproducibility boundary

The project's reproducibility inputs include at least:

```text
Wine version
Wine source archive SHA256
patch filenames
patch SHA256 values
configure architecture set
private runtime prefix
validated build dependencies
```

Changing one of those inputs can change the produced runtime.

A successful compilation after changing an input is not by itself proof that
the new runtime is equivalent to the verified build.

## Relationship to other documentation

For exact Wine source patch behavior, see:

```text
PATCHES.md
```

For GameGuard lifecycle and compatibility boundaries, see:

```text
GAMEGUARD-COMPAT.md
```

For supported distributions and package dependencies, see:

```text
DISTRO-SUPPORT.md
```

For installation and runtime failures, see:

```text
TROUBLESHOOTING.md
```

This document defines the Wine build pipeline and the validation boundaries
between source, build artifacts and the installed private runtime.

