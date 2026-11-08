# v0.2.0: platform-independent dependency preflight

This is an experimental, read-only module. The production installer remains
`scripts/install.sh` from v0.1.1 until the new dependency flow is fully tested.

## Three independent decisions

1. **Distribution verification**: reference-tested platform/version or
   unverified. An unverified platform is not automatically incompatible.
2. **Package backend**: a candidate inferred from `ID` / `ID_LIKE`, then
   checked against an actual executable and native package database.
3. **Build environment**: independent compiler, headers, libraries and ABI
   checks. The experimental standalone build audit now performs compile/link probes.

The package *recipe* is separate from the detected backend. A derivative
declaring `ID_LIKE=arch` can be considered a pacman candidate, but is not
automatically assigned a validated dependency package list.

## Commands

```bash
bash scripts/platform-audit.sh
bash tests/test-platform-detect.sh
bash tests/test-build-env.sh
bash scripts/build-env-audit.sh
bash tests/test-pacman-deps.sh
bash scripts/pacman-deps-audit.sh
bash tests/test-pacman-prepare.sh
bash scripts/pacman-deps-prepare.sh --plan
bash tests/test-manual-deps.sh
bash scripts/manual-deps-prepare.sh --check
bash tests/test-v020-dependencies.sh
bash scripts/v020-dependencies.sh --check
bash tests/test-install-deps-only.sh
bash scripts/install.sh --deps-only
bash tests/test-configure-only.sh
```

These commands do not invoke sudo, install packages, update repositories,
download Wine, create Wine prefixes, or modify OS packages. The build audit
creates and removes temporary C/PE test binaries and produces a report. The tests supply synthetic
`os-release` files; they do not change the host's `/etc/os-release`.

## Planned acceptance criteria before integration

- [Implemented experimentally] Add standalone command, pkg-config, header and link probes.
- [Implemented experimentally] Validate native and 32-bit PulseAudio/ALSA
  linkability, MinGW PE32/PE32+ outputs, and selected graphics development
  modules independently of distro-specific file locations.
- [Pending] Broaden Wine configure coverage and verify end-to-end compilation
  before treating a successful audit as a sufficient Wine build gate.
- [Implemented experimentally] Standalone manual setup with complete dependency
  report, `--check` mode and `--interactive` retry loop. Requires explicit
  continuation on unverified platforms; noninteractive invocation reports and
  exits, never waits for input. No package installation is performed.
- Noninteractive mode must emit a report and exit rather than prompt.
- [Implemented experimentally] Read-only pacman recipe audit for 40 roots,
  including `vulkan-headers`, validated for package availability on CachyOS.
- [Implemented experimentally] A separately invoked `--install` mode requires
  a terminal, prints missing packages, asks the user to type `INSTALL`, then
  relies on a second pacman confirmation. `--plan` is read-only and the default.
- [Pending] Test real automated dependency installation in a fresh CachyOS VM.
  Avoid `pacman -Sy` partial upgrades and never silently initiate a full
  system upgrade.
- Maintain the existing four pinned Wine patches and the Wine 11.6 build path.
- Keep v0.1.1 tags, release archives, and main unchanged.

CachyOS remains **unverified** until a full GameGuard/MU Online end-to-end test.

## Current validator limitations

The experimental independent audit is now included in the development
branch's `scripts/install.sh` dependency stage; it is **not** released yet. A `V020_BUILD_ENV_PREFLIGHT_PASS=True` result
means only that all current *experimental* probes passed; it is not a claim
that Wine `./configure` or `make` will succeed. The check prints
`MISSING` entries for individual failed probes and exits non-zero if any fail.
No interactive retry flow is implemented at this phase.

## CachyOS pacman recipe (read-only)

`bash scripts/pacman-deps-audit.sh` validates platform/backend/multilib,
then classifies 40 package roots as installed, available, or not found.
It uses only `pacman -Qq`, `pacman -Si`, and `pacman-conf --repo-list`;
there is no `sudo`, synchronization, package transaction, or Wine build.
Because `pacman -Si` reads the local sync database, a stale sync database
can produce false unavailability and must never cause an automatic `-Sy`.
The script does not confer support status on other Arch derivatives.

**Not implemented:** automatic transaction execution and interactive retry.

## Experimental opt-in package installer

`bash scripts/pacman-deps-prepare.sh --plan` performs a read-only audit.
If every package is already installed, it runs the separate build preflight.
`bash scripts/pacman-deps-prepare.sh --install` requires an interactive
terminal and the exact typed consent `INSTALL` before executing a standard
`pacman -S --needed` transaction. Pacman asks for its own confirmation.
No upgrade, sync-only transaction, or `--noconfirm` is used. After installation,
the module rechecks package roots and runs the independent build preflight.
On absent/unverified backend it exits rather than guessing package names;
interactive guided-manual retry is a later development step.

The mocked transaction tests are scoped to CachyOS and intentionally do not
exercise a real package installation. Before release, test the installer with
missing dependencies on a disposable VM snapshot.

## Assisted manual dependency checks (experimental)

`bash scripts/manual-deps-prepare.sh --check` runs a one-time, non-mutating
build-environment validation. It exits nonzero if anything is missing.
`bash scripts/manual-deps-prepare.sh --interactive` (only with a terminal)
asks for confirmation on unverified distributions and offers **R** to rerun
the same independent audit or **Q** to quit. It never guesses Gentoo package
names or modifies Portage settings. On Gentoo, users need to adjust package
USE flags and ABI_X86 as required; exact recommendations are pending a Gentoo
VM test. When a terminal is unavailable, --interactive prints the audit and
exits with status 3. This helper currently does **not** continue to Wine
builds; wiring it into the main installer is a future phase.

## v0.2.0 standalone dispatcher (no legacy installer changes)

`bash scripts/v020-dependencies.sh --check` selects the experimental
CachyOS pacman **read-only** plan or an independent manual build check.
`--prepare` routes CachyOS to the explicitly confirmed pacman
installation flow and other distributions to an interactive manual retry.
The dispatcher does not invoke `scripts/install.sh` or begin Wine/MU setup.
The stable Fedora/Nobara/Ubuntu production tag v0.1.1 remains unchanged.
The v0.2.0 development branch now contains an isolated dependency-gate
integration in `scripts/install.sh`: portable distros route to Pacman
or manual checks, while the existing DNF/APT package recipes are retained.
Portable systems use the common compiler/link/ABI validator in place of
hardcoded Fedora/Ubuntu audio .pc file paths. An unverified distribution
requires explicit interactive confirmation for a full installation.

`bash scripts/install.sh --deps-only` executes patch SHA checks and the
full dependency validation stage, but skips package installation, requires
no MU Windows installer, and exits before downloading Wine or creating any
Wine prefix. `--skip-deps` remains an install-time flag and must still run
build/link/ABI validation. A successful `--deps-only` check is **not**
evidence that Wine itself builds or that GameGuard works. Full E2E tests
remain pending, including a fresh VM Pacman transaction.

Safety policy: a detected package manager does **not** imply a validated
recipe. A non-CachyOS Arch derivative uses manual setup until its recipe
has been independently verified. The `--check` mode never changes packages.

## Experimental Wine configure-only checkpoint

`bash scripts/install.sh --configure-only --base PATH` (development branch
only) requires no official MU Windows installer. It runs platform detection,
source/patch SHA verification, the dependency/ABI checks, then downloads
and verifies Wine 11.6 source, applies four pinned patches and executes
Wine configure with `--enable-archs=i386,x86_64`.
The script exits **before** make, private-runtime installation, prefix
creation and game installation. It prints
`V020_WINE_CONFIGURE_ONLY_PASS=True` on success.
It preserves the configured build directory under the chosen base for the
normal full installer, which can validate and reuse it later.

**This mode does modify its private workspace and downloads Wine sources.**
Only `--deps-only` is read-only. The configure-only mode should be run in a
fresh test workspace; verify free disk space and the existing release's
`configure` checks. The full installer is not yet end-to-end verified
on CachyOS.

## Case-insensitive explicit confirmations

The development branch accepts `CONTINUE` and `INSTALL` regardless of
letter case (`continue`, `Continue`, `install`, etc.). Empty values,
extra spaces and other words still fail. The same shared helper is used
for the main installer, manual dependency assistant and pacman installer.
Run `bash tests/test-consent.sh` for regression checks. This does not
change a process that has already started from an older checkout.

## Experimental build-only checkpoint

`bash scripts/install.sh --build-only --jobs 2 --base PATH` performs
preflight, validates the four pinned patches, reuses the already configured
Wine 11.6 source/build directories and runs `make -j2`. On success it
validates PE32/PE32+ and UNIX audio build artifacts and exits **before**
`make install`, prefix creation or game installation.
The build is written into the private PATH workspace; it is not read-only.
The standard full installation can reuse it later. `--jobs N` overrides
`nproc` without changing the default behaviour for existing users.
For the 5.78 GiB RAM CachyOS VM, begin with `--jobs 2` to reduce peak
memory pressure. More concurrency can be tested separately.
Run `bash tests/test-build-only.sh` before attempting compilation.

## Experimental private Wine runtime-only checkpoint

After a successful `--build-only` validation, run
`bash scripts/install.sh --runtime-only --jobs 2 --base PATH` to reuse
the patched and configured build, repeat the artifact checks, execute
`make install` into the **private runtime directory** and verify binaries,
architecture, checksums and equality to build artifacts. It then exits
**before** creating a Wine prefix or installing MU Online. The current
runtime-only implementation still runs an incremental `make -j2` check
before `make install`, so this is not a pure no-compilation mode.

This stage changes private workspace files and can use substantial disk space.
Run `bash tests/test-runtime-only.sh` (read-only) before attempting it.
If a private runtime already exists, installation refuses to overwrite it.
This is experimental and not a full release installation.

## Experimental prefix-only checkpoint: no repeat build or install

The CachyOS VM has now compiled Wine 11.6 and installed the verified private
runtime. The `--prefix-only` mode uses the existing runtime directly:
`bash scripts/install.sh --prefix-only --base PATH`. It checks the existing
Wine version, pinned patch hashes, all nine build/runtime artifact pairs,
and the absence of a pre-existing prefix. It then executes the original
stage 3A first-`wineboot` code and preserves its verification of runtime
ownership, 32/64-bit prefix structure and GameGuard absence.
It exits immediately after stage 3A, before MU Online installation.

The prefix-only path deliberately skips Wine source extraction, `configure`,
`make`, and `make install`; it still requires explicit consent for
unverified distributions. Do not run it again after a successful prefix
creation: it refuses to overwrite an existing prefix.
Run `bash tests/test-prefix-only.sh` before the first real attempt.

Note: this standalone checkpoint does not yet make the normal full installer
resume automatically from an existing runtime/prefix. Such reuse needs a
separate, carefully tested path to avoid silent modifications or loss of data.

## Resume after confirmed pristine prefix (experimental)

`bash scripts/install.sh --resume-from-prefix --installer PATH_TO_OFFICIAL_EXE --base PATH`
uses the previously verified private Wine runtime and existing WoW64 prefix.
It never starts Wine download, configure, build, make install, or wineboot.
Before changing the prefix it checks pinned patch SHA values, matches all nine
built/runtime artifact pairs, confirms the prefix contains both i386 and
x86_64 Windows components, and refuses to proceed if MU or the GameGuard
service/driver already exists. It then executes existing unmodified stages
3B..3E: official MU client installation, service-record compatibility setup,
launcher creation and desktop integration. This mode **does install MU** and
requires the user's supplied official Windows installer; it is not a dry run.
On unverified distributions it requires the explicit interactive CONTINUE
confirmation. Tests: `bash tests/test-resume-from-prefix.sh`.
If any stage fails, inspect logs before trying again: the initial prefix
pristine-state guard may reject an incomplete MU install. Never remove an
existing prefix automatically.
