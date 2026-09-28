# Troubleshooting

This document covers diagnosis of the MU Online Linux installer and the
private Wine runtime created by it.

Start with the exact installer error and the log produced by the stage that
failed. Do not replace the private Wine runtime with system Wine, manually copy
GameGuard files, or modify the GameGuard service record as a first response to
an error.

## Installation logs

The installer stores its logs under:

```text
<base>/logs/
```

The principal installation logs are:

```text
wine-11.6-configure.log
wine-11.6-build.log
wine-11.6-install.log
prefix-first-wineboot.log
mu-official-installer.log
ggkernel64-service-query.log
```

The exact base directory is printed by the installer.

When a build, private-runtime installation, first wineboot, or official MU
installer stage fails, preserve the complete log. The installer may also print
the final 120 lines automatically, but the complete file is the preferred
diagnostic source.

## Do not treat a long build as a hang

Building Wine is CPU-intensive and may take a significant amount of time.

The build runs as a normal foreground:

```text
make -C <build-directory> -j<jobs>
```

The installer heartbeat is informational only. It reports elapsed time, log
activity and process information while the real `make` process continues in
the foreground.

There is no normal timeout that kills a slow Wine build merely because it
takes a long time.

A build failure is determined by the exit status from `make`.

When the build fails, inspect:

```text
<base>/logs/wine-11.6-build.log
```

The installer also prints:

```text
--- BUILD LOG TAIL ---
```

and searches the log for common failure patterns such as:

```text
error:
fatal error:
undefined reference
collect2: error
make: ***
```

Do not terminate a build solely because output has paused while compiler
processes are still active.

## Private runtime installation may also take time

Stage 2E installs the compiled Wine tree into the private runtime using:

```text
make -C <build-directory> install
```

This stage also has a heartbeat and does not use a normal elapsed-time timeout.

Its log is:

```text
<base>/logs/wine-11.6-install.log
```

If `make install` fails after partially creating the runtime, the installer
does not silently delete it.

The partial runtime is preserved under a name of the form:

```text
wine-11.6-mu.failed-install.<timestamp>
```

Do not use that preserved failed runtime as the normal game runtime. It exists
for diagnosis.

## Wine source download fails

The Wine source archive is downloaded with curl using redirects and retries.

If downloading fails completely, the installer stops with:

```text
Wine source download failed
```

Check basic network connectivity and whether the Wine source URL is reachable.

Do not replace the configured Wine archive with an arbitrary Wine source
version.

The installer expects its pinned Wine version and SHA256.

## Cached Wine archive checksum mismatch

A cached archive whose checksum does not match the expected SHA256 is not
reused.

The installer preserves it under a name similar to:

```text
<archive>.bad.<timestamp>
```

and attempts to obtain the required source again.

This is expected fail-safe behavior.

Do not rename the rejected archive back to the normal cache filename.

## Newly downloaded Wine archive checksum mismatch

A newly downloaded archive is verified before it becomes the active cache.

If its SHA256 is wrong, the installer preserves it under a name similar to:

```text
<archive>.bad-sha.<timestamp>
```

and stops with:

```text
downloaded Wine archive checksum mismatch
```

Treat this as an integrity problem.

Do not bypass the SHA256 check.

## Configure did not produce Makefile or config.status

A successful Wine configure stage must produce both:

```text
Makefile
config.status
```

Errors such as:

```text
configure did not produce Makefile
configure did not produce config.status
```

mean the configure stage did not reach the state required by the installer.

Inspect:

```text
<base>/logs/wine-11.6-configure.log
```

Do not proceed directly to `make` until configure succeeds.

## Existing incomplete build directory

The installer may reuse an existing build directory only when it contains both:

```text
Makefile
config.status
```

Otherwise it stops with:

```text
build directory exists but is not a complete configured build
```

Do not manually fabricate either file.

Determine why the previous configure attempt was incomplete before deciding
whether to preserve, archive, or remove that build directory.

## Wrong WoW64 architecture configuration

The verified runtime is configured with:

```text
--enable-archs=i386,x86_64
```

The resulting build configuration must report:

```text
PE_ARCHS=i386 x86_64
```

An error such as:

```text
unexpected PE_ARCHS
```

means the build is not the expected combined i386/x86_64 Wine configuration.

Do not continue with an x86_64-only build.

## PulseAudio was not enabled

The installer reads Wine's configured build variables and requires a non-empty:

```text
PULSE_LIBS
```

It also checks that:

```text
winepulse.drv
```

is not disabled.

Typical hard failures are:

```text
PulseAudio was not enabled by Wine configure
winepulse.drv is disabled
```

Return to the dependency stage and verify the required PulseAudio development
packages and pkg-config metadata for the distribution.

Do not work around the check by deleting Wine's PulseAudio driver requirement.

## ALSA was not enabled

The same policy applies to ALSA.

The installer requires a non-empty:

```text
ALSA_LIBS
```

and an enabled:

```text
winealsa.drv
```

Typical hard failures are:

```text
ALSA was not enabled by Wine configure
winealsa.drv is disabled
```

Verify both the native development dependencies and the distribution-specific
multilib audio metadata described in `DISTRO-SUPPORT.md`.

## GnuTLS development headers were not detected

The installer requires the Wine configure log to contain successful GnuTLS
header detection.

A failure appears as:

```text
GnuTLS development headers were not detected by Wine configure
```

The dependency roots are:

```text
Fedora: gnutls-devel
Ubuntu: libgnutls28-dev
```

After correcting the dependencies, Wine must be configured again so the
configure result reflects the available development files.

Simply installing the package after configure without regenerating the build
configuration is not sufficient.

## GnuTLS cipher support was not detected

The configure log must also show successful detection of:

```text
gnutls_cipher_init
```

Otherwise the installer stops with:

```text
Wine configure did not validate GnuTLS cipher support
```

Treat this as an incomplete GnuTLS development environment or stale configure
result.

Do not suppress the validation.

## Schannel was disabled

The installer explicitly rejects a Wine configure result containing:

```text
no schannel support
```

The hard failure is:

```text
Wine configure disabled Schannel support
```

A Wine binary that compiles successfully without Schannel is not considered a
valid MU runtime by this project.

Correct the GnuTLS development environment and reconfigure Wine.

## Wine build fails

The canonical failure is:

```text
Wine build failed with rc=<value>
```

Use the complete build log:

```text
<base>/logs/wine-11.6-build.log
```

First identify the earliest meaningful compiler or linker failure rather than
only the final recursive `make` error.

Do not delete the source, build tree or log until the root cause is understood.

## Private Wine runtime installation fails

The canonical failure is:

```text
Wine runtime installation failed with rc=<value>
```

Use:

```text
<base>/logs/wine-11.6-install.log
```

If the runtime directory had already begun to be populated, the installer
preserves it as:

```text
<runtime>.failed-install.<timestamp>
```

That preserved directory is evidence of the failed install, not a supported
runtime to launch MU with.

## Private Wine executable is missing after installation

After `make install`, the installer requires at least:

```text
<runtime>/bin/wine
<runtime>/bin/wineboot
<runtime>/bin/wineserver
```

If one is missing, diagnose the `make install` result rather than falling back
to system Wine.

The project deliberately pins its own private runtime.

## First wineboot uses the wrong Wine

During fresh-prefix creation, the installer resolves and monitors the Wine
runtime used for the prefix.

It expects all prefix-related Wine processes to come from the private runtime.

Failures include:

```text
PATH resolves wine outside private runtime
PATH resolves wineboot outside private runtime
PATH resolves wineserver outside private runtime
foreign Wine runtime was observed during prefix creation
```

Do not fix these errors by modifying the prefix with another Wine version.

Determine why PATH or process ownership points outside the project runtime.

## First wineboot fails

The first fresh-prefix initialization is logged in:

```text
<base>/logs/prefix-first-wineboot.log
```

A failed initialization ends with:

```text
first wineboot failed with rc=<value>
```

The installer attempts to stop its private wineserver and preserves the failed
prefix under a name similar to:

```text
prefix.failed-wineboot.<timestamp>
```

Do not reuse the preserved failed prefix for a normal installation.

Inspect the wineboot log first.

## Wine processes remain after prefix initialization

The installer intentionally stops the prefix before moving to the next stage.

An error such as:

```text
wineserver did not stop cleanly
```

means the prefix did not reach the required idle state.

Do not kill unrelated Wine or wineserver instances globally.

The installer uses a private runtime and prefix specifically so diagnosis can
remain scoped to MU.

## Official MU installer is missing

The project does not redistribute the proprietary MU installer.

A valid installer path must be supplied by the user.

Typical failures include:

```text
official MU installer path is required
installer does not exist
MU installer missing
```

Verify the path passed to:

```text
--installer
```

and do not place the proprietary installer inside the project repository.

## Official MU installer differs from the reference build

The installer records the supplied MU installer's SHA256.

The verified reference installer SHA256 is:

```text
8219cae729d8b09fffc07eca9893e0e6365cc0549f0a449a1e2489b1a2253df9
```

A different installer is not automatically rejected solely for being
different, but the installer prints:

```text
WARNING: installer differs from the build used for the verified reference reproduction.
```

This means the supplied proprietary installer is outside the exact reference
reproduction.

Do not interpret the warning as proof that a newer or different installer is
broken.

## Running the graphical MU installer

When the official graphical installer opens, keep the default installation
directory:

```text
C:\Program Files (x86)\Webzen\Mu
```

Do not launch MU automatically when installation finishes.

The compatibility service record is intentionally configured only after the
official installation has completed and the prefix is idle.

Launching MU from the graphical installer can start GameGuard too early and
invalidate the expected prelaunch state.

## Official MU installer fails

The installer log is:

```text
<base>/logs/mu-official-installer.log
```

A non-zero return code produces:

```text
MU installer failed with rc=<value>
```

The installer prints the final 120 log lines and attempts to stop the private
wineserver.

Inspect the complete log before changing the prefix.


## MU was launched during installation

The installer requires a clean prelaunch state after the official MU installer
has finished.

Before the compatibility service record is created, none of these should yet
exist:

```text
<Mu directory>/GameGuard/
GGKernel64.sys
GGKernel64 service record
```

If MU is launched automatically from the official graphical installer,
GameGuard may initialize before the compatibility setup stage.

Typical failures include:

```text
GameGuard directory already exists; MU may have been launched during installation
GGKernel64 service exists before compatibility service setup
GGKernel64.sys exists before first MU launch
```

If this happens, do not manually delete individual GameGuard files or registry
values and continue as though the prelaunch state had remained clean.

Determine the actual state of the prefix first.

For a clean reference installation, leave the "launch MU" option disabled when
the official installer finishes.

## What the installer does with GameGuard

The project does not redistribute, copy, restore, inject or patch
`GGKernel64.sys`.

Before the first user launch, the installer creates only the Wine SCM
compatibility service record required for the normal GameGuard lifecycle.

The service record contains:

```text
DisplayName  REG_SZ         GGKernel64
ErrorControl REG_DWORD      1
ImagePath    REG_EXPAND_SZ  \??\C:\Program Files (x86)\Webzen\Mu\GameGuard\GGKernel64.sys
Start        REG_DWORD      3
Type         REG_DWORD      1
```

GameGuard itself remains responsible for creating and managing its driver file
during the normal game startup process.

The expected state at the end of installation is therefore:

```text
GGKernel64 service record: present
GGKernel64.sys:            absent
GameGuard directory:       absent
MU game process:           not started
```

The absence of `GGKernel64.sys` before the first real MU launch is intentional,
not an installation failure.

## GameGuard service-record setup fails

Before modifying the registry, the installer creates and verifies a backup of:

```text
system.reg
user.reg
userdef.reg
```

under a directory similar to:

```text
<base>/backups/pre-ggkernel64-seed-<timestamp>/
```

If writing or validating the service record fails, the installer stops its
private Wine processes and restores those registry files from the backup.

The rollback marker is:

```text
GG_SERVICE_SEED_ROLLED_BACK=True
```

Do not manually repeat only part of the registry write after a rollback.

The correct next step is to diagnose why the service-record stage failed.

## GGKernel64 registry query fails

The live service-record query is written to:

```text
<base>/logs/ggkernel64-service-query.log
```

A query failure produces:

```text
GGKernel64 service query failed
```

The installer then rolls the registry change back.

Inspect the complete query log before changing `system.reg`.

## GGKernel64 live service validation fails

The installer verifies all five expected live registry values.

A failure produces:

```text
GGKernel64 live service record validation failed
```

This means the result returned by Wine's registry interface did not exactly
match the expected service definition.

Do not work around this by weakening or skipping the service validation.

## GGKernel64 offline service validation fails

After Wine is fully stopped, the installer checks the persisted service record
directly in:

```text
<base>/prefix/system.reg
```

The expected persisted section must occur exactly once and contain the required
service markers.

A failure produces:

```text
GGKernel64 offline service record validation failed
```

This check is distinct from the live `reg.exe query` check.

Both live and persisted state must be valid.

## Wine does not stop after GameGuard service setup

After creating the service record, the installer deliberately stops its
private wineserver so that the next MU launch begins from a clean process state.

Failures include:

```text
Wine did not stop after GGKernel64 service seed
Wine processes remain after GGKernel64 service seed
```

Do not use a global command that kills every Wine or wineserver process on the
machine.

Other applications may use unrelated Wine runtimes.

Diagnosis should remain scoped to the MU prefix and private runtime.

## GameGuard files appear before first user launch

At the end of installation, the installer checks again that neither the
GameGuard directory nor `GGKernel64.sys` exists.

Failures include:

```text
GameGuard directory unexpectedly exists after service seed
GGKernel64.sys unexpectedly exists after service seed
GGKernel64.sys exists before first user launch
GameGuard directory exists before first user launch
```

Such a state means something launched or modified GameGuard earlier than the
verified lifecycle expects.

Do not "fix" this by manually supplying another `GGKernel64.sys`.

## MU launcher is missing or damaged

The generated launcher is stored at:

```text
<base>/bin/mu-online
```

It is expected to be executable and syntactically valid.

The launcher checks for:

```text
private Wine runtime
private wineserver
Wine prefix
Wine registry
Mu.exe
main.exe
GGKernel64 compatibility service record
```

Typical launcher-side failures are printed with the prefix:

```text
MU Online launcher:
```

Examples include:

```text
private Wine runtime is missing
private wineserver is missing
Wine prefix is missing
Wine registry is missing
Mu.exe is missing
main.exe is missing
GGKernel64 Wine SCM compatibility record is missing
```

These are state-integrity errors.

Do not bypass them by launching `Mu.exe` with arbitrary system Wine.

## Launcher resolves the wrong Wine

The launcher pins:

```text
<base>/runtime/wine-11.6-mu/bin/wine
<base>/runtime/wine-11.6-mu/bin/wineserver
```

and verifies that PATH resolution still points to those private executables.

Failures include:

```text
PATH resolves wine outside the private runtime
PATH resolves wineserver outside the private runtime
```

The normal launcher must not fall back to a system Wine installation.

## Launcher does not modify GameGuard

The generated launcher is intentionally passive with respect to GameGuard
service and driver state.

It must not:

```text
add or rewrite the GGKernel64 registry service
copy GGKernel64.sys
restart wineserver as a GameGuard workaround
```

Its job is to validate the prepared private environment and execute:

```text
Mu.exe
```

using the pinned private Wine runtime.

If GameGuard fails at runtime, do not add service or driver mutation commands
to the launcher as a troubleshooting shortcut.

## Desktop shortcut cannot be created

The installer first tries:

```text
xdg-user-dir DESKTOP
```

and otherwise falls back to an existing:

```text
~/Desktop
```

or:

```text
~/Pulpit
```

directory.

If none can be determined, it stops with:

```text
cannot determine desktop directory
```

Fix the user's desktop-directory configuration rather than pointing the
installer at `$HOME` itself.

## Installer refuses to overwrite a desktop entry

Generated project-managed desktop files contain:

```text
X-MUOnline-Linux-Managed=true
```

If the intended application-menu or desktop target already exists without this
marker, the installer stops with:

```text
refusing to overwrite unmanaged desktop entry
```

This is intentional protection against destroying an unrelated user-created
shortcut.

Inspect the existing file before deciding what to do with it.

## Legacy Wine shortcut

A recognized legacy `Mu.desktop` Wine shortcut may be archived rather than
deleted.

Its backup is stored under a path similar to:

```text
<base>/backups/desktop-shortcuts/<timestamp-pid>/Mu.desktop
```

The installer may also preserve the icon from that recognized legacy entry.

This archive is internal to the MU installation base; it should not leave
duplicate backup shortcuts on the desktop.

## Desktop entry exists but does not launch MU

The generated desktop shortcut executes the private project launcher rather
than Wine directly.

The corresponding launcher is:

```text
<base>/bin/mu-online
```

If double-clicking the desktop entry produces no useful visible error, run that
launcher from a terminal so launcher or Wine diagnostics remain visible.

The desktop entry itself uses:

```text
Terminal=false
```

so a terminal run is preferable when diagnosing a launch failure.

## Capturing a first-launch failure

For runtime diagnosis, run the private launcher from a terminal instead of
starting MU through system Wine or opening `Mu.exe` directly.

The launcher normally defaults Wine debugging to:

```text
WINEDEBUG=-all
```

through its `MU_WINEDEBUG` setting.

Do not change the runtime, prefix or GameGuard files merely to obtain a log.

First reproduce the problem with the normal private launcher and capture the
terminal output.

## Wine Gecko dialog on first launch

During verified E2E testing, a Wine Gecko installation dialog appeared on the
first user launch.

If this standard Wine dialog appears, choose:

```text
Install
```

and allow Wine to install Gecko.

This dialog is not, by itself, evidence of a GameGuard failure.

The current installer does not treat the appearance of that dialog as an
installation error.

## Historical `[FCS WebAPI] Failed to respond` case

During Ubuntu-family validation, an earlier Wine build completed while GnuTLS
development support had not been detected.

Wine configure had reported missing GnuTLS development headers and no Schannel
support.

The game then reached launch but repeatedly showed:

```text
[FCS WebAPI] Failed to respond
```

After installing the required Ubuntu GnuTLS development package:

```text
libgnutls28-dev
```

and rebuilding Wine with GnuTLS/Schannel enabled, the game proceeded normally.

This historical case is why the current installer now hard-fails configure
unless all of these checks pass:

```text
GNUTLS_HEADER_DETECTED=True
GNUTLS_CIPHER_DETECTED=True
SCHANNEL_ENABLED=True
```

If the current installer has already completed with all three checks passing,
do not automatically assume every later WebAPI/network symptom has the same
cause.

Collect fresh runtime evidence first.

## GameGuard behavior during the first real launch

The installer deliberately finishes before starting MU.

Its final state reports:

```text
GAME_STARTED=False
GGKERNEL64_SERVICE_RECORD_SEEDED=True
GGKERNEL64_DRIVER_COPIED=False
GAMEGUARD_PATCHED=False
```

The next step is the real user launch.

During that launch, the expected lifecycle is:

```text
launcher
  -> Mu.exe
  -> main.exe
  -> GameGuard
  -> GameGuard-managed GGKernel64.sys
  -> login
  -> character selection
  -> world
```

Do not treat the prelaunch absence of the GameGuard directory or driver as a
problem.

Those artifacts are expected to appear only as GameGuard performs its normal
runtime initialization.

## Do not bypass GameGuard when troubleshooting

The supported compatibility path does not rely on bypassing the anti-cheat.

Do not use troubleshooting changes that:

```text
fake successful driver loading
patch MU Online
patch GameGuard
disable GameGuard
manually provide GGKernel64.sys
hide processes or modules from GameGuard
force fake success return values
```

Such changes would no longer represent the verified project architecture.

Troubleshooting should identify the actual failing stage while preserving the
normal GameGuard lifecycle.

## What a successful installation means

The installer's final validation verifies that the following are ready before
the first user launch:

```text
private Wine 11.6 runtime
private wineserver
Wine prefix
system.reg
Mu.exe
main.exe
MU launcher
application-menu entry
desktop entry
GGKernel64 compatibility service record
```

It simultaneously verifies that these have not yet been supplied or started by
the installer:

```text
GGKernel64.sys
GameGuard directory
MU game process
```

The final instruction is:

```text
NEXT_STEP=RUN_MU_LAUNCHER
```

Installer completion therefore means the environment is prepared for the real
first launch. It does not mean GameGuard has already been run.

