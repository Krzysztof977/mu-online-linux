# Architecture

This document describes the architecture of the MU Online Linux project as
implemented by the canonical installer and generated runtime components.

It focuses on ownership boundaries, installation stages, persistent state,
runtime isolation and the transition from installation to the first real MU
Online launch.

Detailed subsystem behavior is documented separately in the files referenced
near the end of this document.

## Architectural goals

The project is designed around several explicit boundaries:

```text
do not redistribute the proprietary MU Online client
do not redistribute GameGuard binaries
do not provide GGKernel64.sys
do not patch Mu.exe
do not patch main.exe
do not patch GameGuard binaries
do not disable GameGuard
do not fake kernel-driver success
do not depend on the host system Wine for normal operation
```

Instead, the project:

```text
builds a private patched Wine runtime
creates an isolated Wine prefix
runs the official user-supplied MU installer
prepares the Wine SCM compatibility state required before first launch
creates a pinned launcher
creates managed desktop integration
leaves first real MU/GameGuard launch to the user
```

## High-level system model

The complete architecture can be represented as:

```text
Linux host
  |
  +-- distribution dependencies
  |
  +-- MU Online Linux installation base
        |
        +-- cache/
        |     |
        |     +-- verified Wine source archive
        |
        +-- work/
        |     |
        |     +-- patched Wine source
        |     +-- configured Wine build tree
        |
        +-- runtime/
        |     |
        |     +-- private Wine 11.6 runtime
        |
        +-- prefix/
        |     |
        |     +-- isolated Wine prefix
        |     +-- installed MU Online client
        |     +-- GGKernel64 SCM compatibility record
        |
        +-- bin/
        |     |
        |     +-- mu-online launcher
        |
        +-- logs/
        |
        +-- backups/
              |
              +-- selected recoverable installer state
```

The normal desktop shortcut does not execute Wine directly.

It executes the project launcher, which then selects the private Wine runtime
and isolated prefix.

## Ownership model

Different parts of the final installation have different owners.

### Linux distribution

The Linux distribution owns:

```text
system compiler toolchains
development libraries
system package database
desktop environment
host graphics and audio stack
```

The project may install required distribution packages through the supported
dependency stage, but it does not replace the distribution package manager.

### MU Online Linux project

The project owns:

```text
private Wine source/build workflow
Wine compatibility patches
private Wine runtime
Wine prefix initialization
GGKernel64 compatibility service record
project launcher
project-managed desktop entries
project logs
project backup directories
```

### User

The user supplies the official MU Online Windows installer.

The repository does not contain that proprietary installer.

### Official MU installer

The official MU installer owns installation of the MU client files inside the
Wine prefix, including:

```text
Mu.exe
main.exe
```

The project validates these outputs but does not create or patch them.

### GameGuard

GameGuard remains responsible for supplying and managing its runtime files,
including:

```text
GameGuard/
GGKernel64.sys
```

The project does not bundle, copy, restore or inject `GGKernel64.sys`.

## Repository layout

The release repository contains project source and documentation such as:

```text
README.md

scripts/
  install.sh

patches/
  0001-ntdll-ntloaddriver-scm.patch
  0002-ntdll-wow64-stack-semantics.patch
  0003-kernelbase-urlescape-sentinel.patch
  0004-ntoskrnl-gameguard-compat.patch

docs/
  BUILDING-WINE.md
  DISTRO-SUPPORT.md
  GAMEGUARD-COMPAT.md
  PATCHES.md
  TROUBLESHOOTING.md
  ARCHITECTURE.md

checkpoints/
  ...
```

The repository must not contain proprietary MU or GameGuard binaries.

## Installer interface

The canonical installer is:

```text
scripts/install.sh
```

Its primary invocation is:

```text
install.sh --installer /path/to/MU-installer.exe
```

Supported primary options include:

```text
--installer PATH
--base PATH
--skip-deps
```

`--installer` supplies the official Windows installer.

`--base` changes the installation workspace.

`--skip-deps` skips dependency installation but does not convert missing
requirements into supported state.

## Default installation base

The default installation base is:

```text
$HOME/.local/share/mu-online-linux
```

The base is intentionally user-owned rather than a system-wide Wine
installation prefix.

## Persistent path model

The important paths below the selected base are:

```text
<base>/cache
<base>/work
<base>/runtime
<base>/prefix
<base>/logs
<base>/bin
<base>/backups
```

The current Wine-specific paths are:

```text
source archive:
  <base>/cache/wine-11.6.tar.xz

patched source:
  <base>/work/wine-11.6-patched

build tree:
  <base>/work/build-wow64

private runtime:
  <base>/runtime/wine-11.6-mu

Wine prefix:
  <base>/prefix

launcher:
  <base>/bin/mu-online
```

Keeping source, build output, installed runtime and prefix separate is a core
architectural property.

## Installation state machine

The installer performs a preflight followed by ten major progress stages.

The ten major stages are:

```text
2A  System dependencies
2B  Wine source and patches
2C  Configure Wine 11.6
2D  Build Wine 11.6
2E  Install private Wine runtime

3A  Create Wine prefix
3B  Install MU Online
3C  Configure GameGuard service record
3D  Create MU Online launcher
3E  Desktop integration
```

These stages intentionally separate:

```text
host preparation
Wine source preparation
Wine compilation
runtime installation
prefix initialization
proprietary client installation
GameGuard compatibility preparation
normal launcher creation
desktop integration
```

## Preflight

Before the ten major progress stages, the installer performs preflight checks.

These checks establish the environment needed by the later stages before
expensive compilation or proprietary installation begins.

Platform and distribution support details are documented in:

```text
DISTRO-SUPPORT.md
```

## Stage 2A: system dependencies

Stage 2A prepares and validates the native dependencies required for the Wine
build and runtime.

This includes native compiler/toolchain requirements and the development
libraries needed for graphics, audio and networking.

The architecture intentionally keeps dependency installation separate from Wine
source acquisition and compilation.

## Stages 2B through 2E: private Wine pipeline

Stages 2B through 2E create the project's private Wine runtime.

Their responsibilities are:

```text
2B:
  acquire verified Wine source
  validate source archive
  apply verified repository patches

2C:
  configure WoW64 build
  validate architectures
  validate audio configuration
  validate GnuTLS / Schannel

2D:
  compile Wine
  validate build outputs
  keep runtime and prefix absent

2E:
  install private Wine runtime
  validate runtime version and contents
  compare installed compatibility artifacts with build artifacts
  keep prefix absent
```

The full build architecture is documented in:

```text
BUILDING-WINE.md
```

The exact patch set is documented in:

```text
PATCHES.md
```

## Private Wine boundary

Normal MU operation is tied to the project runtime:

```text
<base>/runtime/wine-11.6-mu
```

The project does not rely on whichever `wine` command happens to be installed
globally on the host.

This isolation is maintained during prefix creation and in the generated
launcher.

## Stage 3A: fresh Wine prefix

Stage 3A creates the Wine prefix from zero.

Its source marker is:

```text
MU_INSTALLER_STAGE_3A_FRESH_PREFIX
```

Its success marker is:

```text
INSTALLER_STAGE_3A_FRESH_PREFIX_PASS=True
```

Before initialization, the prefix must not already exist.

## First wineboot ownership

The initial prefix is created using the private runtime.

The relevant environment includes:

```text
WINEPREFIX=<base>/prefix
WINESERVER=<base>/runtime/wine-11.6-mu/bin/wineserver
WINEDEBUG=-all
```

The installer also verifies that command resolution for Wine-related
executables points into the private runtime.

This prevents prefix initialization by an unrelated system Wine installation.

## Runtime observation during prefix creation

During first `wineboot`, the installer observes the processes associated with
the target `WINEPREFIX`.

It checks that the custom private runtime is actually used and detects foreign
Wine runtime processes associated with that prefix.

Successful validation includes:

```text
FIRST_WINEBOOT_RUNTIME_OWNERSHIP_OK=True
PINNED_RUNTIME_FROM_FIRST_WINEBOOT=True
```

## Failed prefix preservation

If the first `wineboot` fails after creating partial prefix state, the partial
prefix is not silently accepted.

It is preserved under a timestamped path of the form:

```text
prefix.failed-wineboot.<timestamp>
```

This preserves diagnostic state while preventing accidental continuation with
an ambiguous prefix.

## Prefix shutdown after initialization

After successful initialization, the project uses the private `wineserver` to
stop the prefix cleanly.

The installer requires:

```text
PREFIX_WINESERVER_STOPPED=True
```

before the pristine prefix is accepted.

## Pristine prefix validation

A valid newly created prefix must contain normal Wine registry state,
including:

```text
system.reg
user.reg
userdef.reg
```

The installer also validates expected WoW64 layout.

Successful structural validation includes:

```text
WOW64_PREFIX_LAYOUT_OK=True
```

## Pristine GameGuard boundary

At the end of Stage 3A:

```text
MU Online is not installed
GGKernel64 service record is absent
GGKernel64.sys is absent
```

The corresponding state includes:

```text
MU_PRESENT=False
GGKERNEL64_SERVICE_PRESENT=False
GGKERNEL64_SYS_PRESENT=False
```

This creates a known baseline before the official MU installer is run.

## Prefix idle boundary

Stage 3A finishes only after verifying that the target prefix has no remaining
Wine processes.

The intended end state includes:

```text
PREFIX_IDLE=True
PREFIX_CREATED_FROM_ZERO=True
```

## Stage 3B: official MU installation

Stage 3B executes the official user-supplied MU installer inside the prepared
prefix.

Its source marker is:

```text
MU_INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL
```

Its success marker is:

```text
INSTALLER_STAGE_3B_OFFICIAL_MU_INSTALL_PASS=True
```

## MU installation preconditions

Before the official installer is started, the project requires:

```text
valid Wine prefix
private Wine runtime
private wineserver
MU installation directory absent
GGKernel64 service record absent
GGKernel64.sys absent
idle target prefix
```

This avoids mixing the proprietary client installation with prior GameGuard
runtime state.

## User-supplied proprietary installer

The installer records information about the supplied MU installer, including:

```text
file size
SHA256
```

A known reference installer can be recognized.

If the supplied installer differs from the reference build, the installer may
warn rather than treating every different official build as automatically
invalid.

## Graphical MU installation

The official installer is run through the private runtime and target prefix.

The user is instructed to use the normal installation directory:

```text
C:\Program Files (x86)\Webzen\Mu
```

The user is also instructed not to launch MU automatically at the end of the
graphical installation.

This distinction is important because the installer must establish the clean
pre-launch GameGuard baseline before the first actual game start.

## MU client validation

After the official installer exits, the project requires:

```text
Mu.exe
main.exe
```

inside the expected MU directory.

The files are inspected for expected executable architecture.

The installer also records their SHA256 values.

When a known reference official installer is being used, the corresponding
known client hashes can be validated.

## GameGuard remains unstarted after Stage 3B

After MU installation but before Stage 3C, the project explicitly requires:

```text
GameGuard directory absent
GGKernel64 service record absent
GGKernel64.sys absent
```

Successful pre-launch validation includes:

```text
GAMEGUARD_PRELAUNCH_BASELINE_OK=True
```

Stage 3B ends with state equivalent to:

```text
OFFICIAL_MU_INSTALL_COMPLETED=True
DRIVER_COPIED=False
SERVICE_SEEDED=False
MU_STARTED=False
GAMEGUARD_STARTED=False
```

## Stage 3C: GGKernel64 service-record seed

Stage 3C prepares the Wine SCM compatibility record required before the first
normal GameGuard launch.

Its source marker is:

```text
MU_INSTALLER_STAGE_3C_GGKERNEL64_SEED
```

Its success marker is:

```text
INSTALLER_STAGE_3C_GGKERNEL64_SEED_PASS=True
```

This stage prepares service metadata.

It does not supply the driver binary.

## Stage 3C preconditions

Before modifying registry service state, the project requires:

```text
valid Wine registry
installed Mu.exe
installed main.exe
private Wine runtime
private wineserver
no GameGuard directory
no existing GGKernel64 service record
no GGKernel64.sys
idle target prefix
```

## Registry transaction boundary

Before writing the compatibility service record, the installer backs up:

```text
system.reg
user.reg
userdef.reg
```

The backup is verified.

If service-record setup fails, the stage contains rollback logic to restore
those registry files.

The rollback state can report:

```text
GG_SERVICE_SEED_ROLLED_BACK=True
```

This makes the service seed a controlled state transition instead of an
unprotected registry edit.

## GGKernel64 service record

The compatibility record contains five values:

```text
DisplayName  REG_SZ         GGKernel64
ErrorControl REG_DWORD      1
ImagePath    REG_EXPAND_SZ  \??\C:\Program Files (x86)\Webzen\Mu\GameGuard\GGKernel64.sys
Start        REG_DWORD      3
Type         REG_DWORD      1
```

The `ImagePath` points to the location where GameGuard is expected to manage its
driver during normal operation.

The project does not create that file during installation.

## Service-record validation

The installer validates the seeded service record in two forms:

```text
live Wine registry query
persisted offline system.reg state
```

Successful validation includes:

```text
GGKERNEL64_LIVE_SERVICE_RECORD_OK=True
GGKERNEL64_OFFLINE_SERVICE_RECORD_OK=True
```

## Wine shutdown after service seed

After writing and validating the service record, Wine is fully stopped.

The stage requires:

```text
WINE_FULLY_STOPPED_AFTER_SEED=True
PREFIX_IDLE_AFTER_SERVICE_SEED=True
```

This ensures later processes reload the persisted service state rather than
continuing with stale in-memory SCM state.

## Driver ownership after service seed

After Stage 3C:

```text
service record exists
GameGuard directory is still absent
GGKernel64.sys is still absent
```

The installer explicitly reports:

```text
SERVICE_RECORD_SEEDED=True
GGKERNEL64_SYS_PRESENT=False
DRIVER_COPIED=False
FINAL_PRELAUNCH_STATE_READY=True
```

The service record and driver file therefore have deliberately different
ownership.

The project prepares the former.

GameGuard remains responsible for the latter.

## Stage 3D: launcher

Stage 3D creates the normal runtime entry point:

```text
<base>/bin/mu-online
```

Its success marker is:

```text
INSTALLER_STAGE_3D_LAUNCHER_PASS=True
```

The launcher is generated only after the private runtime, prefix, MU files and
GGKernel64 compatibility service record have been validated.

## Launcher self-location

The launcher derives its installation base from its own filesystem location.

From that base it reconstructs the expected:

```text
private Wine runtime
Wine prefix
MU installation directory
Mu.exe
main.exe
```

This avoids depending on the caller's current working directory.

## Launcher integrity checks

Before starting MU, the launcher requires:

```text
private wine executable
private wineserver executable
Wine prefix
Wine registry
Mu.exe
main.exe
GGKernel64 compatibility service record
```

It also checks that command resolution for Wine components does not escape the
private runtime.

## Launcher execution model

The launcher changes into the MU installation directory and starts:

```text
./Mu.exe
```

through the private Wine executable.

The runtime environment includes the project prefix and pins the private
wineserver.

The normal launcher therefore implements the transition:

```text
desktop/menu entry
  -> project launcher
  -> private Wine
  -> prepared prefix
  -> Mu.exe
```

## Launcher Wine debugging

The launcher supports a project-specific Wine debug setting through:

```text
MU_WINEDEBUG
```

Its normal default corresponds to:

```text
WINEDEBUG=-all
```

Changing debugging verbosity does not change ownership of the runtime or
prefix.

## Launcher negative guarantees

The generated launcher is deliberately passive with respect to GameGuard
service and driver state.

The installer validates:

```text
LAUNCHER_MUTATES_GGKERNEL64_SERVICE=False
LAUNCHER_COPIES_GGKERNEL64_DRIVER=False
LAUNCHER_RESTARTS_WINESERVER=False
LAUNCHER_USES_ABSOLUTE_PRIVATE_WINE=True
LAUNCHER_PINS_WINESERVER=True
```

The launcher is therefore not a recurring registry or driver workaround.

Its normal job is to validate the prepared state and start `Mu.exe`.

## Stage 3D does not start the game

Creating and validating the launcher does not execute it.

Stage 3D ends with:

```text
GAME_STARTED=False
```

This preserves the boundary between installation and the first real user
launch.

## Stage 3E: desktop integration

Stage 3E creates desktop-environment integration for the private launcher.

Its success marker is:

```text
INSTALLER_STAGE_3E_DESKTOP_INTEGRATION_PASS=True
```

Two managed entries are involved:

```text
application-menu entry
desktop entry
```

## Application-menu location

The application-menu entry is created below:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/applications
```

with the filename:

```text
mu-online.desktop
```

## Desktop directory resolution

The installer first tries:

```text
xdg-user-dir DESKTOP
```

If that is unavailable or unsuitable, it falls back to an existing:

```text
$HOME/Desktop
```

or:

```text
$HOME/Pulpit
```

directory.

The installer does not accept `$HOME` itself as the desktop directory.

## Desktop entry target

The user-visible desktop file is:

```text
MU Online.desktop
```

The generated entry executes:

```text
<base>/bin/mu-online
```

rather than invoking Wine directly.

## Managed-entry ownership marker

Project-owned desktop files contain:

```text
X-MUOnline-Linux-Managed=true
```

If the intended menu or desktop target already exists without that marker, the
installer refuses to overwrite it.

The corresponding protection is:

```text
refusing to overwrite unmanaged desktop entry
```

This prevents an unrelated user-created file from being silently destroyed.

## Legacy Wine shortcut migration

The installer recognizes a specific legacy Wine-style:

```text
Mu.desktop
```

shortcut by its content.

A recognized legacy shortcut can be moved into an internal backup directory:

```text
<base>/backups/desktop-shortcuts/<timestamp-pid>/Mu.desktop
```

rather than being left as a duplicate desktop entry.

Its existing icon can be retained for the newly generated project entry.

## Desktop file properties

The application entry contains properties including:

```text
Type=Application
Name=MU Online
Terminal=false
StartupNotify=true
Categories=Game;
StartupWMClass=mu.exe
X-MUOnline-Linux-Managed=true
```

The menu entry mode is:

```text
0644
```

The desktop copy is made executable with mode:

```text
0755
```

Both entries are validated to ensure they execute the private project launcher.

## Final installation validation

After Stage 3E, the installer performs a final cross-component validation.

The final validation requires at least:

```text
private Wine
private wineserver
Wine prefix
Wine registry
Mu.exe
main.exe
project launcher
desktop integration
GGKernel64 compatibility service record
```

The private Wine version is checked again.

The final pre-launch state also requires the absence of:

```text
GGKernel64.sys
GameGuard directory
```

## Final installer state

A successful installation reports state including:

```text
INSTALLATION_COMPLETE=True
PRIVATE_WINE_READY=True
MU_INSTALLED=True
GGKERNEL64_SERVICE_RECORD_SEEDED=True
GGKERNEL64_DRIVER_COPIED=False
GAMEGUARD_PATCHED=False
GAME_STARTED=False
LAUNCHER_READY=True
DESKTOP_INTEGRATION_READY=True
NEXT_STEP=RUN_MU_LAUNCHER
```

This state is an important architectural boundary.

The installer is complete, but the first real MU/GameGuard runtime lifecycle
has not yet occurred.

## First real user launch

The first real game start happens only after installation, when the user runs:

```text
<base>/bin/mu-online
```

or the managed desktop/menu entry that points to it.

The prepared path is:

```text
project launcher
  -> private Wine 11.6
  -> isolated Wine prefix
  -> Mu.exe
  -> normal MU client lifecycle
  -> GameGuard runtime lifecycle
```

The detailed GameGuard lifecycle and Wine compatibility model are documented
in:

```text
GAMEGUARD-COMPAT.md
```

## GameGuard runtime ownership boundary

Before first user launch:

```text
GGKernel64 service metadata exists
GGKernel64.sys does not exist
GameGuard directory does not exist
```

The installer does not pre-populate GameGuard runtime files.

During normal game operation, GameGuard remains responsible for creating and
managing its own files according to its normal lifecycle.

The Wine compatibility work exists to let that lifecycle interact with Wine's
SCM and driver interfaces without converting the project into a GameGuard
replacement.

## Wine patch boundary

The project's Wine modifications live in the private Wine source/runtime
boundary.

They do not modify:

```text
Mu.exe
main.exe
GameGuard binaries
```

The exact source changes are documented in:

```text
PATCHES.md
```

## SCM compatibility boundary

The project seeds the `GGKernel64` service metadata because Wine SCM state must
exist before GameGuard attempts the normal driver-load path.

The project does not interpret that metadata as proof that a kernel driver has
already loaded successfully.

Driver creation and runtime behavior remain separate from service-record
preparation.

## Prefix process isolation

Several stages explicitly stop the target prefix and verify it is idle before
moving to the next state.

This is used around:

```text
first wineboot completion
official MU installation
GGKernel64 service-record seeding
```

The purpose is to avoid depending on stale Wine processes or stale in-memory
service state.

## Private wineserver isolation

Operations associated with the MU prefix pin:

```text
<base>/runtime/wine-11.6-mu/bin/wineserver
```

rather than issuing a global process kill.

This is an important isolation property on systems that may simultaneously run
other Wine workloads.

## Failure-state preservation

The installer prefers preserving diagnostically useful partial state over
silently treating it as valid.

Examples include:

```text
bad Wine source archive:
  preserved with a bad-archive name

failed Wine source download checksum:
  preserved with a bad-SHA name

failed runtime install:
  partial runtime preserved with a timestamped failed-install name

failed first wineboot:
  partial prefix preserved with a timestamped failed-wineboot name

GGKernel64 service seed:
  registry backup exists for rollback

recognized legacy desktop shortcut:
  archived under the installation base
```

This makes failure recovery explicit.

## Validation architecture

The installer uses layered validation rather than relying on one final
success return code.

Examples include:

```text
input SHA256 validation
patch-state validation
source structural validation
configure-feature validation
build artifact validation
PE/ELF architecture validation
build-to-runtime byte comparison
private Wine version validation
prefix layout validation
process ownership validation
proprietary MU output validation
live service-record validation
offline registry validation
launcher source validation
desktop ownership validation
final cross-component validation
```

A later stage therefore consumes already validated state from the preceding
stage.

## Integrity boundaries

Several different integrity concepts coexist.

### Repository integrity

Repository scripts, patches and documentation are project-controlled inputs.

Patch SHA256 values are pinned.

### Upstream Wine integrity

The Wine source archive is version-pinned and SHA256-verified before use.

### Build integrity

Important build outputs are checked for presence and architecture.

Installed private-runtime copies are compared with the corresponding build
artifacts.

### Proprietary installer provenance

The user-supplied MU installer is recorded and hashed.

The project does not redistribute it.

### Runtime state integrity

The launcher validates that required project-owned and client-owned state is
present before starting MU.

## Security boundaries

The architecture deliberately avoids several unsafe shortcuts.

It does not require:

```text
replacing system Wine
running MU through arbitrary host Wine
globally killing unrelated Wine processes
shipping a GameGuard driver
forcing NtLoadDriver to return success
forcing DriverEntry to return success
patching the MU client
patching GameGuard
disabling GameGuard
hiding processes
hiding modules
```

Where compatibility behavior is partial, the project documents that boundary
rather than treating unsupported behavior as implemented.

## Desktop safety boundary

Desktop integration is considered user-owned surface area.

For that reason the installer distinguishes between:

```text
project-managed entries
unmanaged existing entries
recognized legacy Wine entries
```

Only project-managed targets may be replaced normally.

Recognized legacy entries are archived.

Unmanaged targets are preserved and cause the installer to stop.

## Runtime update boundary

MU Online and GameGuard can update independently of the repository.

For that reason, runtime file hashes observed after an update are not
automatically equivalent to a project source-integrity failure.

The project-controlled compatibility layer is the private Wine runtime and its
documented source patches.

Client updates must be interpreted in that context.

## Logs

Major operations write logs below:

```text
<base>/logs
```

Examples include:

```text
Wine configure log
Wine build log
Wine install log
first wineboot log
official MU installer log
GGKernel64 service-query log
```

The complete logs are the primary diagnostic artifacts.

Terminal summaries and log tails are convenience output.

## Separation of documentation responsibilities

The architecture documentation intentionally avoids duplicating every
implementation detail.

Use:

```text
BUILDING-WINE.md
```

for:

```text
Wine source acquisition
patch application pipeline
configure
build
private runtime installation
build/runtime validation
```

Use:

```text
PATCHES.md
```

for:

```text
exact Wine source modifications
patch file ownership
patch behavior and limitations
```

Use:

```text
GAMEGUARD-COMPAT.md
```

for:

```text
GameGuard lifecycle
GGKernel64 SCM interaction
Wine driver compatibility
security-descriptor compatibility boundaries
first-launch behavior
```

Use:

```text
DISTRO-SUPPORT.md
```

for:

```text
supported Linux distributions
architecture requirements
native packages
dependency differences
```

Use:

```text
TROUBLESHOOTING.md
```

for:

```text
installer failures
build failures
launcher failures
desktop integration problems
runtime diagnosis
known historical failure modes
```

## Canonical implementation

The canonical executable implementation remains:

```text
scripts/install.sh
```

Documentation describes and constrains that implementation.

If documentation and executable behavior ever diverge, the discrepancy should
be investigated explicitly rather than silently assuming one representation is
current.

## Final architecture summary

The project is intentionally structured as a sequence of ownership transfers:

```text
Linux host
  -> validated build environment

upstream Wine source
  -> verified patched source
  -> verified build
  -> private Wine runtime

private Wine runtime
  -> fresh isolated prefix

user-supplied official MU installer
  -> validated MU client inside that prefix

project compatibility preparation
  -> GGKernel64 SCM service metadata

project launcher
  -> pinned private Wine execution path

desktop integration
  -> project launcher

first real user launch
  -> Mu.exe
  -> normal MU/GameGuard runtime lifecycle
```

The installer stops before the final runtime lifecycle begins.

Its final responsibility is to prepare and validate the environment.

The next responsibility belongs to the normal MU launcher and, subsequently,
the MU client and GameGuard themselves.

