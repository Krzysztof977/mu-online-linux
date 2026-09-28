# Licensing scope

The default license for original MU Online Linux project code and
documentation is the MIT License in the repository root `LICENSE` file,
except where another license is explicitly identified.

## Wine-derived patches

The files below are source-code patches against Wine:

- `patches/0001-ntdll-ntloaddriver-scm.patch`
- `patches/0002-ntdll-wow64-stack-semantics.patch`
- `patches/0003-kernelbase-urlescape-sentinel.patch`
- `patches/0004-ntoskrnl-gameguard-compat.patch`

They modify or contain diff context from Wine source files.

Wine source code is distributed under the GNU Lesser General Public License,
version 2.1 or, at the user's option, any later version.

Accordingly, the Wine-derived patch material is distributed under
LGPL-2.1-or-later rather than being relicensed under the repository's
default MIT license.

The corresponding license text is included as:

`LICENSES/LGPL-2.1-or-later.txt`

The patch files themselves are intentionally left byte-for-byte unchanged so
that their pinned SHA256 values remain valid.

## Upstream Wine

This repository does not redistribute the complete Wine source archive.

The installer downloads the pinned upstream Wine source separately and
verifies its SHA256 checksum before applying the project patches.

Wine remains an independent upstream project and is not covered by the
repository's MIT license.

## MU Online and GameGuard

This repository does not distribute proprietary MU Online or nProtect
GameGuard executables, drivers, installers or runtime files, including
`GGKernel64.sys`.

Those components are not covered by the MU Online Linux project's MIT
license.
