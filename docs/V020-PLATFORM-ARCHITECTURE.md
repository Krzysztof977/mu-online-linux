# v0.2.0: platform-independent dependency preflight (Phase 1)

This is an experimental, read-only module. The production installer remains
`scripts/install.sh` from v0.1.1 until the new dependency flow is fully tested.

## Three independent decisions

1. **Distribution verification**: reference-tested platform/version or
   unverified. An unverified platform is not automatically incompatible.
2. **Package backend**: a candidate inferred from `ID` / `ID_LIKE`, then
   checked against an actual executable and native package database.
3. **Build environment**: independent compiler, headers, libraries and ABI
   checks. Currently `not_checked` in Phase 1.

The package *recipe* is separate from the detected backend. A derivative
declaring `ID_LIKE=arch` can be considered a pacman candidate, but is not
automatically assigned a validated dependency package list.

## Commands

```bash
bash scripts/platform-audit.sh
bash tests/test-platform-detect.sh
```

Neither command invokes sudo, installs packages, updates repositories, downloads
Wine, creates Wine prefixes, or modifies OS packages. The tests supply synthetic
`os-release` files; they do not change the host's `/etc/os-release`.

## Planned acceptance criteria before integration

- Add standalone command, pkg-config, header and link probes.
- Validate 64-bit and 32-bit audio and ABI requirements independently of the
  distro name; executable linker checks must complement `.pc` discovery.
- Add a controlled manual retry loop for unknown/unsupported backends.
- Noninteractive mode must emit a report and exit rather than prompt.
- Add a pacman package recipe validated inside CachyOS. The first dependency
  transaction must require explicit approval and avoid `pacman -Sy` partial
  upgrades. Never silently initiate a full system upgrade.
- Maintain the existing four pinned Wine patches and the Wine 11.6 build path.
- Keep v0.1.1 tags, release archives, and main unchanged.

CachyOS remains **unverified** until a full GameGuard/MU Online end-to-end test.
