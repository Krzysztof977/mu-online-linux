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
- Add a controlled manual retry loop for unknown/unsupported backends.
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

The standalone audit intentionally is **not** hooked into production
`scripts/install.sh` yet. A `V020_BUILD_ENV_PREFLIGHT_PASS=True` result
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
