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
- Add a pacman package recipe validated inside CachyOS. The first dependency
  transaction must require explicit approval and avoid `pacman -Sy` partial
  upgrades. Never silently initiate a full system upgrade.
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
