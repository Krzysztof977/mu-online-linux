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

The installer currently supports:

- Fedora
- Nobara Linux (`ID=nobara`, Fedora/DNF backend)
- Ubuntu and Ubuntu-based systems reporting `ID=ubuntu`

Fully tested reference systems:

| Distribution | Architecture | Status |
| --- | --- | --- |
| Fedora 44 | x86_64 | Full E2E verified |
| Nobara Linux 44 | x86_64 | Full E2E verified |
| Kubuntu 26.04.1 / Ubuntu 26.04 base | x86_64 | Full E2E verified |

Fedora and Nobara releases other than 44, and Ubuntu releases other
than 26.04, are not currently reference-tested.

Other distribution families such as Arch Linux and openSUSE are not yet
supported by the installer.

## Requirements

You need:

- an x86_64 Linux system
- internet access
- sufficient disk space to build Wine and install MU Online
- sudo access for system build dependencies
- the official MU Online Windows installer obtained separately

The MU Online installer is not included in this repository.

## Installation

For version 0.1.1, the recommended entry point is the tagged bootstrap
script. The official MU Online Windows installer must already be downloaded
separately from Webzen and present locally.

Before running the command below:

1. The command is an example. Replace
   `/path/to/official-MU-installer.exe` with the actual path to the official
   MU Online installer on your computer. Keep the path in quotes, especially
   if it contains spaces.
2. The full installation can take **30 minutes or more**, depending on CPU
   performance, storage speed, network speed, and package download times.
   Building Wine is the longest stage and may appear inactive for periods of
   time. Do not interrupt the installer or reboot the system unless an actual
   error is reported.
3. If Wine asks to install **Wine Mono** or **Wine Gecko**, choose
   **Install**. If both prompts appear, install both components.
4. When the installation finishes, the installer prints the next step and
   launch instructions in the terminal.
5. On the first launch, a small dialog may appear with garbled or unreadable
   text because of the game's legacy character encoding. This is expected;
   click **OK** and continue.
6. The bootstrap downloads and verifies only the MU Online Linux
   compatibility package. It does not download or redistribute MU Online,
   nProtect GameGuard, or other proprietary game files.

Example:

~~~bash
curl -fsSL https://raw.githubusercontent.com/Krzysztof977/mu-online-linux/v0.1.1/bootstrap.sh | bash -s -- --installer "/path/to/official-MU-installer.exe"
~~~

The bootstrap downloads the matching versioned release archive, verifies its
SHA256 checksum, extracts it to a temporary directory, runs the archived
`scripts/install.sh` with the supplied arguments, and removes the temporary
files after the installer exits.

Advanced users may instead use a tagged source checkout:

~~~bash
git clone https://github.com/Krzysztof977/mu-online-linux.git
cd mu-online-linux
git checkout v0.1.1

./scripts/install.sh \
    --installer "/path/to/official-MU-installer.exe"
~~~

The default private installation area is:

~~~text
~/.local/share/mu-online-linux
~~~

The installer also accepts:

~~~text
--base PATH
    Override the private installation workspace.

--skip-deps
    Do not install system dependencies.

-h, --help
    Show installer usage.
~~~

A normal user should not use `--skip-deps` unless all required dependencies
are already installed.

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

Version 0.1.1 uses the following publication layout:

- repository: `https://github.com/Krzysztof977/mu-online-linux`
- tag: `v0.1.1`
- release archive: `mu-online-linux-0.1.1.tar.gz`
- checksum asset: `SHA256SUMS`
- tagged bootstrap: `bootstrap.sh`

The versioned release archive contains the distributable project code,
patches, licensing material and documentation. It does not contain
proprietary MU Online or GameGuard binaries.

`bootstrap.sh` is intentionally distributed from the tagged Git source rather
than embedded in the release tarball. This allows the tagged bootstrap to pin
the expected SHA256 of the release archive without making the archive digest
depend on the bootstrap file that contains that digest.

The bootstrap verifies the downloaded release archive before invoking the
archived `scripts/install.sh`.
