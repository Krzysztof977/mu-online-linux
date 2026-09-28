# MU Online Linux — automated installer design

> **Historical design document — superseded by the implemented installer.**
>
> This file preserves early design notes for the automated MU Online Linux
> installer. Statements below using terms such as `planned`, `should` or older
> filesystem paths describe design-time intent and may differ from the current
> implementation.
>
> The canonical executable implementation is
> [`scripts/install.sh`](../scripts/install.sh).
>
> Current technical documentation:
>
> - [`ARCHITECTURE.md`](ARCHITECTURE.md)
> - [`BUILDING-WINE.md`](BUILDING-WINE.md)
> - [`PATCHES.md`](PATCHES.md)
> - [`GAMEGUARD-COMPAT.md`](GAMEGUARD-COMPAT.md)
> - [`DISTRO-SUPPORT.md`](DISTRO-SUPPORT.md)
> - [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)
>
> The historical body below is intentionally retained as a design record.
> Current behavior must be taken from the implemented installer and current
> documentation rather than from this superseded proposal.


This document defines the behaviour of the end-user installer:

    setup-mu-online-linux.sh

The manual installation procedure remains the technical source of truth.

The automated installer must perform the same verified steps, but guide
a non-technical Linux user through them interactively.

# 1. Main goal

The expected user workflow should be:

    chmod +x setup-mu-online-linux.sh
    ./setup-mu-online-linux.sh

The user should not need to:

- download Wine manually
- compile Wine manually
- apply Wine patches manually
- create a Wine prefix manually
- know Wine directory layouts
- edit the registry manually
- copy GameGuard files manually
- construct a launcher manually

# 2. Linux preflight

The installer should detect:

- Linux operating system
- x86_64 architecture
- distribution
- package manager
- available disk space
- internet connectivity
- required command-line tools
- compiler/build environment
- required 32-bit and 64-bit development libraries

Supported package-manager adapters are planned for:

    dnf
    apt
    pacman
    zypper

Distribution-specific package installation must be separated from the
common Wine/MU installation logic.

# 3. Dependencies

Before modifying the system, the installer should display:

- detected distribution
- missing packages
- approximate disk requirements
- the package-manager command it intends to run

System package installation may require sudo.

For the verified Fedora 44 x86_64 reference build, the dependency set must
include the PulseAudio and ALSA development packages for both architectures:

    pulseaudio-libs-devel.x86_64
    pulseaudio-libs-devel.i686
    alsa-lib-devel.x86_64
    alsa-lib-devel.i686

The installer must verify that pkg-config can locate both libpulse and alsa
before Wine configure is allowed to continue.

Equivalent package names on other Linux distributions must remain
distribution-specific and should only be marked verified after an actual
build test.

The installer must not modify the user's system Wine installation.

# 4. Wine source acquisition

The installer should automatically obtain the supported Wine source
release from an official Wine source location.

Current project base:

    Wine 11.6

The installer must:

1. download the expected Wine source archive
2. cache it locally where practical
3. verify the downloaded archive
4. refuse to build from a failed verification
5. extract it into the project build workspace

The exact official source URL and expected checksum will be pinned only
after the clean source reproduction has been completed and verified.

# 5. Wine patch validation

Before applying project patches, the installer should verify that the
source tree is the expected supported Wine version.

Each patch should be checked before application.

A patch mismatch must stop installation with a clear error rather than
continuing with a partially patched Wine tree.

Planned patches include:

    0001-ntdll-ntloaddriver-scm.patch
    0002-ntdll-wow64-stack-semantics.patch
    0003-kernelbase-urlescape-sentinel.patch
    0004-ntoskrnl-gameguard-compat.patch

# 6. Isolated Wine build

The project Wine runtime must be built separately from system Wine.

The installer should create its own:

- source directory
- build directory
- installation/runtime directory
- Wine prefix

The system Wine packages and the user's existing Wine prefixes must not
be overwritten.

After Wine configure, the installer must validate the audio configuration
before starting compilation.

The build must stop with a clear error if any of these conditions is true:

    winepulse.drv is present in DISABLED_SUBDIRS
    winealsa.drv is present in DISABLED_SUBDIRS
    PULSE_LIBS is empty
    ALSA_LIBS is empty

This prevents creation of an otherwise functional MU runtime with no audio.

# 7. MU installer discovery

The project must not redistribute the proprietary MU Online installer.

The automated installer should try to locate an existing official MU
installer on the user's disk.

Search order should begin with common user locations such as:

    ~/Downloads
    ~/Pobrane
    ~/Desktop
    ~/Pulpit

The initial search should be limited and fast.

Likely installer names include files containing terms such as:

    MU
    Webzen

and Windows installer extensions such as:

    .exe
    .msi

If exactly one plausible installer is found, the script should show it
to the user for confirmation.

If multiple installers are found, the script should present a numbered
selection list.

If no installer is found, the script should:

1. explain that MU Online itself is not distributed by this project
2. tell the user to obtain the official installer
3. allow the user to enter or select its path
4. re-check the supplied file before continuing

A broader filesystem scan should only be performed if the user chooses
it, because recursively scanning the whole home directory may be slow.

# 8. MU installation

After an installer has been selected, the script should:

1. show the selected installer path
2. start it using the project's isolated Wine runtime
3. allow the normal graphical MU installation to complete
4. wait for Wine processes belonging to this installation step
5. locate the resulting Webzen/Mu installation
6. verify that Mu.exe exists
7. verify that main.exe exists

Client executable hashes may be recorded for diagnostics.

They must not normally be used as permanent acceptance requirements
because official MU updates can change these files.

# 9. GameGuard

The installer must not:

- provide GGKernel64.sys
- copy a captured GGKernel64.sys
- patch GameGuard files
- disable GameGuard
- fabricate driver success

GameGuard must create and manage its normal files and services through
the official client/update process.

# 10. Launcher creation

After successful installation the script should create:

- a command-line launcher under ~/.local/bin
- a freedesktop desktop entry where appropriate

The launcher should automatically use:

- the project Wine runtime
- the project Wine prefix
- the detected MU installation directory

The user should not need to set WINEPREFIX manually.

# 11. First-run assistant

The first normal MU run should be presented as a guided sequence.

Example stages:

    [1/5] Starting MU launcher
    [2/5] Waiting for client update
    [3/5] Starting GameGuard
    [4/5] Waiting for MU main.exe
    [5/5] Game started

The script should explain when the user needs to interact with a
graphical installer, updater or login window.

# 12. Verification

Where practical, the installer should verify:

- custom Wine runtime exists
- expected patched components exist
- prefix exists
- MU installation exists
- Mu.exe exists
- main.exe exists
- launcher exists
- Wine PulseAudio backend exists
- Wine ALSA backend exists
- Wine audio backend initialization does not report the MMDevAPI no-driver error

Diagnostic hashes should be available through a verification mode.

Possible future command:

    ./setup-mu-online-linux.sh --verify

# 13. Re-running the installer

The installer should be safe to run again.

It should detect already completed stages and avoid rebuilding or
reinstalling unnecessarily.

Possible states include:

    Wine source already downloaded
    Wine already built
    prefix already created
    MU already installed
    launcher already created

The installer should offer repair or rebuild operations rather than
silently deleting an existing installation.

# 14. Failure handling

Each major stage should fail explicitly.

The installer should report:

- which stage failed
- which command failed
- where the log was written
- what the user can try next

It should not leave ambiguous messages such as only:

    installation failed

# 15. Logging

Normal installation output should remain understandable to a
non-technical user.

Detailed build and Wine diagnostics should be written to log files.

Verbose Wine tracing should only be enabled for troubleshooting, not for
every normal game launch.

# 16. Project principle

The automated installer and the manual procedure must describe the same
installation process.

The installer must not rely on undocumented fixes, private files,
historical Wine prefixes or manually copied GameGuard material.

Final acceptance criterion:

    clean Linux environment
      -> run setup script
      -> obtain/build patched Wine
      -> locate official MU installer
      -> install MU
      -> launch normally
      -> GameGuard starts normally
      -> login
      -> character selection
      -> world
