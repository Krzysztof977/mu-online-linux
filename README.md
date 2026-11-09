# MU Online Global on Linux with nProtect GameGuard

Linux compatibility project for running the official **MU Online Global**
client with **nProtect GameGuard enabled**.

The project builds a private patched Wine 11.6 runtime, creates an isolated
Wine prefix, installs the official MU Online client supplied by the user,
configures the Wine compatibility required by GameGuard, and creates a normal
desktop launcher.

MU Online and GameGuard binaries are not distributed by this repository.

## Current status

Full end-to-end installation and game launch have been verified on:

- Fedora 44 x86_64
- Kubuntu 26.04.1 x86_64, based on Ubuntu 26.04
- Nobara Linux 44 x86_64
- CachyOS x86_64 (rolling release; verified for v0.2.0)

The verified path includes:

- system dependency installation
- download and SHA256 verification of pristine Wine 11.6 source
- application of the four project Wine patches
- custom WoW64 Wine build
- private Wine runtime installation
- fresh isolated Wine prefix creation
- installation of the official MU Online client
- GGKernel64 service record creation
- GameGuard startup
- MU login
- character selection
- world entry
- working game audio
- desktop launcher creation

The current installer uses Wine 11.6 and does not replace or modify the
system Wine installation.

## GameGuard integrity

GameGuard remains enabled.

The project does not:

- disable GameGuard
- bypass GameGuard checks
- patch MU Online binaries
- patch GameGuard binaries
- fake NtLoadDriver success
- fake GGKernel64 DriverEntry success
- hide processes or modules from GameGuard
- forge anti-cheat responses
- bundle or inject GGKernel64.sys

The working execution path preserves the normal service and driver loading
flow:

```text
Mu.exe
  -> main.exe
  -> GameGuard
  -> GameMon64
  -> NtLoadDriver
  -> Service Control Manager
  -> winedevice.exe
  -> ntoskrnl!ZwLoadDriver()
  -> GGKernel64.sys
  -> DriverEntry
  -> login
  -> character selection
  -> world
```

GameGuard remains responsible for supplying and managing its own driver file.

## Supported distributions

**v0.2.0** retains the tested Fedora, Nobara Linux (`ID=nobara`,
Fedora/DNF backend), and Ubuntu (`ID=ubuntu`, APT backend) installation
paths from v0.1.1. It adds CachyOS with a native Pacman backend, a
40-root package recipe, multilib and compiler/ABI preflight checks.
Generic Arch derivatives are **not** automatically granted
CachyOS support.

Fully tested reference systems:

| Distribution | Architecture | Status |
| --- | --- | --- |
| Fedora 44 | x86_64 | Full E2E verified |
| Nobara Linux 44 | x86_64 | Full E2E verified |
| Kubuntu 26.04.1 / Ubuntu 26.04 base | x86_64 | Full E2E verified |
| CachyOS rolling release (tested on KVM/QEMU, 2026-11-08) | x86_64 | Full E2E verified for v0.2.0 |

The Fedora, Nobara and Kubuntu E2E results were obtained during previous
release verification; v0.2.0 preserves their automatic DNF/APT paths
and passed regression tests, but a separate full v0.2.0 E2E run was
not repeated on those systems. CachyOS completed a full v0.2.0 E2E run.

Fedora and Nobara releases other than 44, and Ubuntu releases other
than 26.04, are not currently reference-tested.

Other Linux x86_64 distributions can also attempt installation with v0.2.0.
On an unverified system, the installer asks for explicit confirmation
before proceeding. Installation and gameplay may work if the required
dependencies and compatibility checks pass, but success is not guaranteed.

## Requirements

You need:

- an x86_64 Linux system
- internet access
- sufficient disk space to build Wine and install MU Online
- sudo access for system build dependencies
- the official MU Online Windows installer obtained separately

The MU Online installer is not included in this repository.

## Installation

### v0.2.0 — Fedora, Nobara, Ubuntu and CachyOS

**v0.2.0 is the current stable release for all four verified reference
systems:** Fedora 44, Nobara Linux 44, Ubuntu 26.04 (including the tested
Kubuntu 26.04.1) and CachyOS rolling x86_64. The same installation command
is used on each system; the installer selects the appropriate native
dependency backend automatically.

Download the official MU Online Windows installer separately from Webzen.
Replace `/path/to/official-MU-installer.exe` below with its actual location
and keep the path quoted:

~~~bash
git clone --branch v0.2.0 \
    https://github.com/Krzysztof977/mu-online-linux.git
cd mu-online-linux
bash scripts/install.sh --installer "/path/to/official-MU-installer.exe"
~~~

On a memory-limited machine, add `--jobs 2` to limit Wine compilation
parallelism, for example:

~~~bash
bash scripts/install.sh --jobs 2 \
    --installer "/path/to/official-MU-installer.exe"
~~~

Alternatively, download the **tagged v0.2.0 bootstrap** and run it with
the same installer path:

~~~bash
curl --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' \
    --output mu-online-linux-bootstrap-v0.2.0.sh \
    https://raw.githubusercontent.com/Krzysztof977/mu-online-linux/v0.2.0/bootstrap.sh
bash mu-online-linux-bootstrap-v0.2.0.sh \
    --installer "/path/to/official-MU-installer.exe"
~~~

The bootstrap downloads the versioned MU Online Linux compatibility
archive, verifies its pinned SHA256 digest and the `SHA256SUMS` release
asset, extracts the archive, invokes the archived installer and cleans
up its temporary files. Neither the bootstrap nor the archive includes
the proprietary MU Online or GameGuard binaries.

**Before installing:**

1. The full installation may take **30 minutes or longer**. Compiling
   Wine is the longest stage; periods without terminal output can be
   normal. Do not interrupt or reboot unless an actual error occurs.
2. If Wine offers to install **Wine Mono** or **Wine Gecko**, choose
   **Install** for the offered components.
3. When the installer completes, follow its printed game-launch instructions.
4. On the first game launch, a dialog may show unreadable text because of
   legacy character encoding; acknowledge it with **OK** and continue.

The default private installation area is:

~~~text
~/.local/share/mu-online-linux
~~~

Additional options include:

~~~text
--base PATH
    Override the private installation workspace.

--jobs N
    Set Wine build parallelism (positive integer).

--skip-deps
    Skip installing system packages (prerequisite validation still applies).

-h, --help
    Show installer usage.
~~~

Normal installations should not use `--skip-deps` unless the required
system dependencies are already installed.

### Distribution-specific dependency handling

The installer separates distribution verification, package-manager
detection and a validated package recipe.

| Tested reference system | Package manager | Dependency recipe |
| --- | --- | --- |
| Fedora 44 x86_64 | DNF | `fedora-v011` |
| Nobara Linux 44 x86_64 | DNF | `fedora-v011` |
| Ubuntu 26.04 / Kubuntu 26.04.1 x86_64 | APT | `ubuntu-v011` |
| CachyOS rolling x86_64 | Pacman | `cachyos-v020` |

- **Fedora / Nobara:** installs required packages using
  `dnf install -y`, retaining the Fedora-family dependency path.
- **Ubuntu / Kubuntu:** uses `apt-get update` followed by
  `apt-get install -y`. Ubuntu-based distributions must report
  `ID=ubuntu` to use the verified Ubuntu recipe.
- **CachyOS:** checks native Pacman, multilib and the verified 40-root
  dependency recipe, installing missing roots with
  `pacman -S --needed` and Pacman's native transaction confirmation.
  It does not add a separate `Type INSTALL` prompt, run `pacman -Sy`
  or silently upgrade the system.

After dependency preparation, the installer builds the pinned private
patched Wine 11.6, initializes its own WoW64 prefix and installs the
user-supplied official MU Online client. GameGuard remains enabled.

**Verification scope:** complete E2E testing of Fedora 44, Nobara 44 and
Kubuntu 26.04.1 was performed for earlier versions; their existing
DNF/APT installation paths are retained in v0.2.0 and regression-tested.
A fresh end-to-end run of v0.2.0 itself was completed on CachyOS in
KVM/QEMU on November 8, 2026 (six virtual Ryzen cores, about 5.78 GiB
RAM). That test does not guarantee every future CachyOS rolling snapshot,
GPU or driver combination.

### Other distributions — experimental (unverified)

**You can try installing v0.2.0 on other, untested Linux x86_64
distributions too.** The installer does not reject an unfamiliar OS solely
because of its name. Instead, it asks whether you want to continue with
an experimental installation. If the dependencies and compatibility
checks pass, the installer may complete successfully and MU Online may
work normally. However, these systems have not been tested end to end,
so successful installation or gameplay cannot be guaranteed.

Run the same `v0.2.0` installer with your own official MU Online Windows
installer. On an unverified distribution, the installer asks once:

~~~text
Type CONTINUE to proceed with experimental installation:
~~~

Type `continue` (or `CONTINUE`; the match is case-insensitive) and press
Enter. Empty input, surrounding spaces and other words are rejected.
The confirmation requires an interactive terminal and is not repeated
by the package-manager or manual-dependency helper.

After you confirm `CONTINUE`, the installer **first attempts to prepare
dependencies automatically** with a recognized, native package manager:
Pacman, DNF or APT. On unverified distributions, these package lists are
**experimental** and do not imply that the OS has passed E2E testing.
For example, Arch Linux can check the 40 Pacman dependency roots and
offer to install available missing packages through Pacman's normal
transaction confirmation; it does not inherit CachyOS's verified status.

**Manual preparation is a fallback**, not the default. If no supported
native package manager is detected, some packages are not available
in its configured repositories, a transaction cannot finish, or required
build checks still fail, the installer shows the missing prerequisites.
Install or supply them manually with your distribution's tools, press
**Enter** to recheck or **Q** to quit. The build/toolchain, 32/64-bit ABI,
graphics, network and audio checks must pass before Wine compilation.
The installer never runs `pacman -Sy` or silently upgrades the system.

Versions outside the tested Fedora/Nobara/Ubuntu reference set are
also classified as unverified. Generic Arch derivatives have not passed
this project's full E2E verification. The experimental path does not
bypass GameGuard or guarantee successful gameplay.

### Previous releases — v0.1.1 (historical)

The earlier **v0.1.1** release remains available for users who
specifically need it. It was tested with Fedora 44, Nobara Linux 44
and Ubuntu 26.04/Kubuntu 26.04.1, but **v0.2.0 is the recommended current
release for those distributions as well**.

[MU Online Linux v0.1.1 — GitHub Release](https://github.com/Krzysztof977/mu-online-linux/releases/tag/v0.1.1)

For a historical checkout, select the old tag explicitly:

~~~bash
git clone --branch v0.1.1 \
    https://github.com/Krzysztof977/mu-online-linux.git
cd mu-online-linux
bash scripts/install.sh --installer "/path/to/official-MU-installer.exe"
~~~

The v0.1.1 tag, published release archive and checksum remain unchanged.

## Installation stages

The automated installer runs ten major stages:

```text
1.  System dependencies
2.  Wine source and patches
3.  Configure Wine 11.6
4.  Build Wine 11.6
5.  Install private Wine runtime
6.  Create Wine prefix
7.  Install MU Online
8.  Configure GameGuard service record
9.  Create MU Online launcher
10. Desktop integration
```

The final progress indicator reaches:

```text
[████████████████████] 10/10 100% ✓ Installation complete
```

A completed progress stage represents an actual completed installer stage.
The progress percentage is based on the ten defined stages rather than an
estimated wall-clock completion percentage.

## Long-running Wine stages

Building Wine may take many minutes, depending on CPU and storage performance.

During the Wine build the installer keeps `make` in the foreground and writes
the complete build output to a log file. A separate heartbeat reports elapsed
time, log activity and relevant compiler/build process counts.

The heartbeat is informational only. It does not impose an automatic build
timeout and does not terminate a slow build merely because output has been
quiet for a period of time.

The private-runtime installation stage also keeps its real `make install`
command in the foreground. Its heartbeat reports elapsed time, log age and
`make` / `install` process activity.

For non-interactive output the heartbeat emits periodic plain-text status
lines without terminal control sequences.

## Private Wine runtime

The project currently uses Wine 11.6.

Official source archive:

```text
https://dl.winehq.org/wine/source/11.x/wine-11.6.tar.xz
```

Expected SHA256:

```text
d49d166975478f609e6a9cdbda0a07c65a3b795e061fc454d3f1034c828d19e0
```

The installer verifies this checksum before extracting or building the source.

The Wine runtime is built and installed privately under the selected project
base. It does not overwrite the system Wine installation.

With the default base, the layout includes:

```text
~/.local/share/mu-online-linux/
├── cache/
├── work/
├── runtime/
│   └── wine-11.6-mu/
├── prefix/
├── logs/
└── bin/
```

The generated MU launcher uses this private runtime and this private prefix.

## Wine patches

The installer applies four compatibility patches:

```text
0001-ntdll-ntloaddriver-scm.patch
0002-ntdll-wow64-stack-semantics.patch
0003-kernelbase-urlescape-sentinel.patch
0004-ntoskrnl-gameguard-compat.patch
```

Each patch has a pinned SHA256 value in the installer.

Before applying a patch, the installer verifies that the repository copy
matches the expected checksum. A checksum mismatch stops the installation.

The patches modify Wine compatibility behavior. They do not patch MU Online
or GameGuard binaries.

## WoW64 build

Wine is built as a combined i386/x86_64 WoW64 runtime.

The installer validates required build outputs before installing the private
runtime and later compares important installed runtime files against their
corresponding build artifacts.

Required runtime components include patched Wine modules such as:

```text
lib/wine/x86_64-unix/ntdll.so
lib/wine/i386-windows/ntdll.dll
lib/wine/x86_64-windows/ntdll.dll
lib/wine/i386-windows/kernelbase.dll
lib/wine/x86_64-windows/kernelbase.dll
lib/wine/i386-windows/ntoskrnl.exe
lib/wine/x86_64-windows/ntoskrnl.exe
```

The installer also validates the installed Wine version before continuing.

## Networking validation

The Wine build must include the GnuTLS development support required for
Wine Schannel.

After Wine configure, the installer checks that GnuTLS headers and the
required cipher API were detected and rejects a configuration that reports
missing Schannel support.

This validation is important because a Wine build can otherwise complete
successfully while lacking networking functionality required by the MU
client.

## Audio validation

The installer validates the development environment needed for the Wine
PulseAudio and ALSA backends before accepting the Wine configuration.

The private runtime is expected to contain:

```text
lib/wine/x86_64-unix/winepulse.so
lib/wine/x86_64-unix/winealsa.so
```

The reference Fedora and Kubuntu installations reached the game world with
working game audio.

## Failure handling

Major build and runtime-installation output is preserved in log files.

If the Wine build or private-runtime installation fails, the installer prints
the relevant return code and the tail of the corresponding log rather than
silently continuing with a partial runtime.

A failed private runtime installation is not accepted as a valid completed
stage.


## MU Online installation

The project does not download or redistribute the proprietary MU Online
installer.

The official Windows installer must be supplied explicitly:

```bash
./scripts/install.sh \
    --installer "/path/to/official-MU-installer.exe"
```

The installer launches it through the project's private Wine runtime and
allows the normal graphical MU installation procedure to run.

The expected installation directory inside the private Wine prefix is:

```text
C:\Program Files (x86)\Webzen\Mu
```

After installation the script verifies that both `Mu.exe` and `main.exe`
exist.

Client executable hashes may change after official MU updates, so they are
useful for diagnostics but are not treated as permanent acceptance
requirements.

## GameGuard service record

The installer creates the Wine registry service record required for the normal
GameGuard driver-loading path:

```text
HKLM\System\CurrentControlSet\Services\GGKernel64
```

The configured image path is:

```text
\??\C:\Program Files (x86)\Webzen\Mu\GameGuard\GGKernel64.sys
```

The service record uses kernel-driver semantics.

The installer does not provide, copy or inject `GGKernel64.sys`.

GameGuard remains responsible for creating and managing its own driver file
during the normal client and anti-cheat lifecycle.

## Launcher

After MU installation and GameGuard service configuration, the installer
creates a private MU launcher below the selected project base.

With the default base this is:

```text
~/.local/share/mu-online-linux/bin/mu-online
```

The launcher automatically selects the project's private Wine runtime and
private Wine prefix.

The user does not need to set `WINEPREFIX` manually.

## Desktop integration

The installer creates:

- an application-menu entry
- an executable desktop shortcut

Both entries launch the private MU launcher rather than system Wine.

Managed desktop entries contain:

```text
X-MUOnline-Linux-Managed=true
```

The installer refuses to silently replace unrelated unmanaged desktop
entries.

A matching legacy Wine-generated MU shortcut may be archived internally
before the managed project shortcut is installed.

## First launch

After successful installation, start **MU Online** using the generated desktop
shortcut or application-menu entry.

The expected launch sequence is:

```text
MU launcher
  -> MU updater/client
  -> GameGuard
  -> login
  -> character selection
  -> world
```

On a fresh Wine environment, a Wine Gecko installation dialog may appear
during the first launch. If it appears, choose **Install**.

A system reboot is not normally required by the project itself.

If the Linux package manager reports that a reboot is recommended after
dependency installation, allow the MU installer process to finish first and
reboot afterward.

## Logs

Installer logs are stored below the selected project base.

With the default base:

```text
~/.local/share/mu-online-linux/logs
```

The Wine build and private-runtime installation stages write their detailed
command output to log files.

The terminal progress display is intentionally less verbose than those logs.

When a build-related stage fails, the installer preserves diagnostic output
and prints a tail of the relevant log.

## Proprietary files

This repository must not contain or redistribute proprietary MU Online or
nProtect GameGuard files.

Do not commit or include in release archives files such as:

- `Mu.exe`
- `main.exe`
- `GameGuard.des`
- `GameMon.des`
- `GameMon64.des`
- `GGKernel64.sys`
- official Webzen MU installers
- complete MU Online client directories

Users must obtain MU Online through the official distribution channel.

## Repository layout

~~~text
README.md
VERSION
CHANGELOG.md
LICENSE

LICENSES/
    licensing details and LGPL-2.1-or-later text

bootstrap.sh
    tagged release bootstrap entry point

scripts/
    automated installer

patches/
    Wine compatibility patches

docs/
    engineering and installation documentation
~~~

Local development checkpoints are intentionally kept outside the public
source tree and outside versioned release archives. The repository
`.gitignore` also protects a local `checkpoints/` directory from accidental
staging.

## Nobara 44 verification (v0.1.1)

Nobara Linux 44 x86_64 completed the normal installer workflow
using the Fedora/DNF backend and private patched Wine 11.6.
MU Online was successfully launched and gameplay confirmed.

E2E-tested scripts/install.sh SHA256:

    34c011d75678e9007336e65a7f6058561dbff682f50b4f9f58686cd7494fdecc

Wine 11.6 and all four compatibility patches remain unchanged.

## Verification history (v0.1.0)

The immediately preceding installer state completed full end-to-end testing
on both reference platforms.

Full-E2E-tested installer SHA256:

```text
e2c82048dfd6d5a41bcb5620056a91861bcba0548e0c6d2d5c5230ec05987b7b
```

That state was verified through installation and real desktop launch to:

```text
GameGuard
  -> login
  -> character selection
  -> world
  -> working audio
```

on:

- Fedora 44 x86_64
- Kubuntu 26.04.1 x86_64

The only subsequent installer change was the Stage 2E private-runtime
installation heartbeat.

That change was validated separately with:

- exact before/after scope audit
- unchanged Stage 2D Wine build section
- unchanged foreground `make install` command
- no runtime-install timeout
- no global process termination
- interactive TTY heartbeat test
- non-TTY heartbeat test
- successful heartbeat shutdown

v0.1.0 installer SHA256:

```text
2daa0ceafe55a12b9c78679505ce3f4dff41ebc8824ad83bca44dca58619a984
```

The v0.1.0 SHA has not been subjected to another complete Wine-build and game
E2E run because its only difference from the preceding E2E-tested state is
the separately scope-audited and runtime-tested Stage 2E heartbeat.

## Documentation status

The automated installer remains the implementation source of truth.

The current production documentation under `docs/` has been reconciled with
the verified implementation. `docs/installer-design.md` and
`docs/manual-install.md` are retained as historical/superseded development
references and carry notices identifying that status.

## Release status

Version 0.2.0 uses the same publication layout established by v0.1.1:

- repository: `https://github.com/Krzysztof977/mu-online-linux`
- tag: `v0.2.0`
- release archive: `mu-online-linux-0.2.0.tar.gz`
- checksum asset: `SHA256SUMS`
- tagged bootstrap: `bootstrap.sh`

The v0.1.1 tag and release assets remain available without modification.

The versioned release archive contains the distributable project code,
patches, licensing material and documentation. It does not contain
proprietary MU Online or GameGuard binaries.

`bootstrap.sh` is intentionally distributed from the tagged Git source rather
than embedded in the release tarball. This allows the tagged bootstrap to pin
the expected SHA256 of the release archive without making the archive digest
depend on the bootstrap file that contains that digest.

The bootstrap verifies the downloaded release archive before invoking the
archived `scripts/install.sh`.
