# GameGuard Compatibility

This document describes the Wine compatibility work used by this project to
allow MU Online to follow its normal GameGuard startup lifecycle on Linux.

The goal is compatibility, not anti-cheat bypassing.

The project does not redistribute or patch MU Online or GameGuard binaries and
does not provide `GGKernel64.sys`.

GameGuard remains responsible for supplying and managing its own driver during
the normal game launch.

## Compatibility model

The verified startup model is:

```text
MU launcher
  -> Mu.exe
  -> main.exe
  -> GameGuard
  -> NtLoadDriver
  -> Wine SCM driver-service handling
  -> winedevice-hosted kernel driver image
  -> normal game continuation
```

The project modifies Wine behavior where the stock implementation does not
provide Windows-compatible behavior required by the observed MU/GameGuard
path.

It does not replace GameGuard's decisions with unconditional success.

## Patch set

The private Wine 11.6 runtime uses four project patches:

```text
0001-ntdll-ntloaddriver-scm.patch
SHA256 128398b6cc9a8be12771df8636e6ab5db96dc68c2ed4dc275045211354e79ab8

0002-ntdll-wow64-stack-semantics.patch
SHA256 507dcf28948909a3d869b58f5ff1aa1272a1c6b6abeb2d42e6350c6ae9cad8a0

0003-kernelbase-urlescape-sentinel.patch
SHA256 98478fac80966bffac650a76e870ba1a39a809eb5d20d783dd8486cb9b628572

0004-ntoskrnl-gameguard-compat.patch
SHA256 d40695dcc32b3f2f5343e4bf1eef5ae7a212da4fdb0f454209f0c1d833721399
```

These hashes are part of the verified installer inputs.

## Patch 0001: NtLoadDriver and NtUnloadDriver through Wine SCM

`0001-ntdll-ntloaddriver-scm.patch` adds a user-mode implementation of:

```text
NtLoadDriver
NtUnloadDriver
```

to Wine's `ntdll`.

The implementation accepts a registry service path under:

```text
\Registry\Machine\System\CurrentControlSet\Services\
```

extracts the service name, loads the required service-control APIs from:

```text
sechost.dll
```

and delegates driver service control to Wine's Service Control Manager.

For a load request it uses:

```text
OpenSCManagerW
OpenServiceW
StartServiceW
```

For an unload request it uses:

```text
OpenSCManagerW
OpenServiceW
ControlService
```

with:

```text
SERVICE_CONTROL_STOP
```

The intent is to let the ordinary Wine service infrastructure handle the
driver service so that the driver image continues to be hosted by
`winedevice`.

The patch does not directly load a Linux kernel module and does not inject a
GameGuard driver from the project.

## NtLoadDriver error propagation

The patch translates relevant Win32 SCM errors to NTSTATUS values instead of
returning unconditional success.

Examples include:

```text
ERROR_ACCESS_DENIED
  -> STATUS_ACCESS_DENIED

ERROR_PRIVILEGE_NOT_HELD
  -> STATUS_PRIVILEGE_NOT_HELD

ERROR_INVALID_PARAMETER
  -> STATUS_INVALID_PARAMETER

ERROR_NOT_ENOUGH_MEMORY
ERROR_OUTOFMEMORY
  -> STATUS_NO_MEMORY

ERROR_FILE_NOT_FOUND
ERROR_PATH_NOT_FOUND
ERROR_SERVICE_DOES_NOT_EXIST
  -> STATUS_OBJECT_NAME_NOT_FOUND

ERROR_SERVICE_ALREADY_RUNNING
  -> STATUS_IMAGE_ALREADY_LOADED

ERROR_SERVICE_NOT_ACTIVE
  -> STATUS_OBJECT_NAME_NOT_FOUND
```

Unmapped service failures become:

```text
STATUS_UNSUCCESSFUL
```

This behavior is important because the compatibility layer preserves failure
information rather than converting every driver-service operation into success.

## NtLoadDriver syscall integration

Patch 0001 also adjusts Wine's generated syscall definitions so that the new
`NtLoadDriver` and `NtUnloadDriver` implementations are used correctly without
also generating conflicting assembly syscall wrappers for those functions.

The affected architecture-specific syscall lists include both i386 and
x86_64 handling.

The patch also updates Wine's syscall-generation metadata so the change remains
consistent when spec/syscall files are regenerated.

## Patch 0002: WoW64 32-bit application stack semantics

`0002-ntdll-wow64-stack-semantics.patch` changes Wine's internal thread-stack
allocation interface by adding a boolean control named:

```text
use_commit_size
```

Most Wine stacks continue to use the original behavior.

The special behavior is enabled only for the 32-bit application stack created
for WoW64.

The affected call uses:

```text
virtual_alloc_thread_stack(..., TRUE, TRUE)
```

where the final `TRUE` selects the compatibility behavior.

Kernel, 64-bit, emulator and native stacks pass:

```text
use_commit_size = FALSE
```

and therefore retain the ordinary path.

## WoW64 StackLimit and guard placement

For the selected 32-bit WoW64 application stack, the patch keeps the full Wine
stack mapping committed but changes the reported committed-stack boundary and
guard placement.

It computes:

```text
stack_base  = view base + view size
stack_limit = stack_base - commit_size
guard       = stack_limit - host_page_size
```

The guard page is moved to the page immediately below that calculated
`StackLimit`.

The resulting TEB value becomes:

```text
StackLimit = StackBase - commit_size
```

for this special path.

The patch explicitly states that the full stack mapping remains committed as
in stock Wine.

This is therefore a targeted stack-semantics compatibility change, not a
general reduction of Wine stack allocation.

## Patch 0003: UrlEscape ANSI sentinel handling

`0003-kernelbase-urlescape-sentinel.patch` changes an ANSI URL-escape result-size
case in Wine's `kernelbase`.

When the caller supplies:

```text
*escaped_len == ~0u
```

the patched behavior does not treat that sentinel as a normal large output
buffer.

Instead it sets:

```text
*escaped_len = lenA + 1
```

and returns:

```text
E_INVALIDARG
```

For ordinary buffer lengths larger than the converted string, the existing
conversion path remains in use.

This is a narrowly scoped API-semantics fix.

## Patch 0004: ntoskrnl compatibility

`0004-ntoskrnl-gameguard-compat.patch` extends Wine's `ntoskrnl.exe`
implementation in three areas used by the observed driver path:

```text
IoCreateDeviceSecure
SeCaptureSecurityDescriptor
KeGetCurrentIrql
```

The implementations are deliberately bounded to behavior actually implemented
by the patch.

Unsupported behavior is reported as unsupported rather than silently treated as
successful.

## IoCreateDeviceSecure

Stock Wine's implementation at the patched location was a semi-stub which
delegated directly to:

```text
IoCreateDevice
```

Patch 0004 adds partial security-descriptor handling.

If SDDL is supplied, the patch:

1. validates the `UNICODE_STRING` byte length,
2. creates a NUL-terminated copy,
3. converts the SDDL using
   `ConvertStringSecurityDescriptorToSecurityDescriptorW`,
4. determines the required security-information flags and access rights,
5. creates the device with `IoCreateDevice`,
6. opens the created device object with `ObOpenObjectByPointer`,
7. applies the security descriptor with `NtSetSecurityObject`.

If the security application fails after the device is created, the patch
deletes the device and clears the returned device pointer.

## IoCreateDeviceSecure limitations

The patch explicitly reports itself as a partial security implementation.

In particular, the source states that the:

```text
DeviceClassGuid registry override
```

is not implemented.

When no SDDL-derived security information is supplied, ordinary
`IoCreateDevice` semantics are preserved.

The patch also maps SDDL conversion failures to meaningful NTSTATUS results such
as:

```text
STATUS_INSUFFICIENT_RESOURCES
STATUS_UNKNOWN_REVISION
STATUS_NOT_IMPLEMENTED
STATUS_INVALID_SECURITY_DESCR
```

rather than manufacturing success.

## SeCaptureSecurityDescriptor

Patch 0004 replaces Wine's stub export for:

```text
SeCaptureSecurityDescriptor
```

with a compatibility implementation for the self-relative descriptor path.

It first validates the output pointer and initializes it to NULL.

A NULL original descriptor succeeds with a NULL captured descriptor.

For:

```text
KernelMode
```

with capture not explicitly requested, a descriptor with revision 1 may be
returned directly.

Otherwise the implementation validates the descriptor and supports copying a
self-relative security descriptor into pool memory.

The copy size comes from:

```text
RtlLengthSecurityDescriptor
```

and allocation uses:

```text
ExAllocatePoolWithTag
```

## SeCaptureSecurityDescriptor limitations

The patch intentionally does not pretend to implement conversion of arbitrary
absolute security descriptors.

If the supplied descriptor is not self-relative on the capture path, it
returns:

```text
STATUS_NOT_IMPLEMENTED
```

The patch comments state that the observed GameGuard WDMSEC path supplies an
already self-relative descriptor.

This limitation is intentional and forms part of the compatibility boundary.

## KeGetCurrentIrql

On x86_64, patch 0004 adds the missing export:

```text
KeGetCurrentIrql
```

The current compatibility implementation is a stub that returns:

```text
0
```

which corresponds to the passive IRQL value expected by the currently
supported path.

This is not the same as forcing a driver load operation itself to return
success.

Driver-service loading still flows through the SCM path implemented by patch
0001, with its own error handling.


## GGKernel64 compatibility service record

The installer prepares the Wine SCM record before the first real MU launch.

The registry service key is:

```text
HKLM\System\CurrentControlSet\Services\GGKernel64
```

The expected values are:

```text
DisplayName  REG_SZ         GGKernel64
ErrorControl REG_DWORD      1
ImagePath    REG_EXPAND_SZ  \??\C:\Program Files (x86)\Webzen\Mu\GameGuard\GGKernel64.sys
Start        REG_DWORD      3
Type         REG_DWORD      1
```

The service record tells the Wine service infrastructure where the
GameGuard-managed kernel driver is expected to appear.

It does not place that driver on disk.

## Registry safety and rollback

Before creating the service record, the installer verifies that the prefix is
idle and creates a backup of:

```text
system.reg
user.reg
userdef.reg
```

under:

```text
<base>/backups/pre-ggkernel64-seed-<timestamp>/
```

The backup is verified before registry modification begins.

If writing or validating the service record fails, the installer stops the
private Wine processes and restores the registry files from that backup.

The rollback marker is:

```text
GG_SERVICE_SEED_ROLLED_BACK=True
```

The service-seed stage is therefore intended to be reversible rather than a
blind registry mutation.

## Live and offline service validation

After writing the five service values, the installer validates the service
record through Wine using:

```text
reg.exe query
```

The output is written to:

```text
<base>/logs/ggkernel64-service-query.log
```

The installer verifies that all expected names, registry types and values are
present.

It then fully stops Wine and verifies the persisted record directly in:

```text
<base>/prefix/system.reg
```

The persisted `GGKernel64` service section must occur exactly once and must
contain the expected service markers.

A valid installation therefore requires both:

```text
live Wine registry validation
offline persisted-registry validation
```

## Required prelaunch state

The compatibility service record is intentionally created before GameGuard has
run.

At the end of installation the verified state is:

```text
GGKernel64 service record: present
GGKernel64.sys:            absent
GameGuard directory:       absent
MU process:                not started
```

The installer explicitly checks that:

```text
GGKernel64.sys
```

has not appeared and that:

```text
GameGuard/
```

does not exist before the first user launch.

This is intentional.

The project prepares Wine for the expected service request but leaves GameGuard
responsible for its own files and runtime initialization.

## Why MU must not be launched during installation

The official MU installer must finish without automatically starting MU.

Starting the game before the compatibility service record has been prepared can
allow GameGuard to initialize against an incomplete Wine environment.

The installer treats early GameGuard artifacts as an invalid prelaunch state.

Examples include:

```text
GameGuard directory already exists
GGKernel64 service already exists
GGKernel64.sys already exists
```

These checks protect the verified installation sequence.

## First real launch

After installation completes, the installer prints:

```text
NEXT_STEP=RUN_MU_LAUNCHER
```

The generated launcher uses the private Wine runtime and the prepared prefix.

The intended runtime chain is:

```text
MU launcher
  -> Mu.exe
  -> main.exe
  -> GameGuard
  -> GameGuard prepares its runtime files
  -> GameGuard requests GGKernel64 driver service loading
  -> NtLoadDriver
  -> Wine SCM
  -> winedevice
  -> driver initialization
  -> login
  -> character selection
  -> world
```

The installer itself does not execute this final chain.

It deliberately stops at a clean prelaunch state.

## Ownership of GGKernel64.sys

`GGKernel64.sys` is not:

```text
bundled
downloaded by this project
copied by the installer
restored from a project backup
injected into the prefix
embedded in the launcher
```

The expected source of the file is GameGuard itself during normal runtime.

The installer verifies this policy both before and after service-record setup.

Its final summary includes:

```text
GGKERNEL64_SERVICE_RECORD_SEEDED=True
GGKERNEL64_DRIVER_COPIED=False
GAMEGUARD_PATCHED=False
GAME_STARTED=False
```

## Launcher boundaries

The generated launcher is also validated so that it does not contain logic to:

```text
rewrite the GGKernel64 service
copy GGKernel64.sys
restart wineserver as a GameGuard workaround
```

The launcher validates the prepared environment and starts:

```text
Mu.exe
```

with:

```text
private Wine
private wineserver
private prefix
```

The GameGuard compatibility work remains in the private Wine runtime rather
than being hidden in shell-side launch hacks.

## DriverEntry results

A driver initialization failure status observed in Wine diagnostics is not, by
itself, sufficient to determine whether the complete MU/GameGuard startup
failed.

The relevant test is the complete runtime result:

```text
GameGuard initialization
login
character selection
world entry
```

Do not replace a real `DriverEntry` result with a fabricated success value.

The compatibility implementation must preserve actual return behavior from the
Wine driver path.

## Compatibility is not a bypass

The project does not intentionally:

```text
disable GameGuard
skip GameGuard startup
patch GameGuard binaries
patch MU Online binaries
fake NtLoadDriver success
force DriverEntry success
hide processes
hide modules
manually inject GGKernel64.sys
replace GameGuard validation decisions
```

The purpose of the Wine patches is to implement or correct Windows behavior
needed by the observed application and driver path.

Where behavior is not implemented, the patches use real error status values
such as:

```text
STATUS_NOT_IMPLEMENTED
STATUS_INVALID_PARAMETER
STATUS_INVALID_SECURITY_DESCR
STATUS_UNSUCCESSFUL
```

rather than treating unsupported behavior as successful.

## Known compatibility boundaries

The patch set is not a general-purpose implementation of every Windows kernel
driver behavior.

Important explicit boundaries include:

```text
IoCreateDeviceSecure:
  DeviceClassGuid registry override is not implemented.

SeCaptureSecurityDescriptor:
  arbitrary absolute security-descriptor capture is not implemented.

KeGetCurrentIrql:
  current x86_64 compatibility implementation returns passive IRQL 0.
```

These limitations are documented because future GameGuard versions may exercise
paths that the currently verified build does not.

A future incompatibility should therefore be diagnosed from new runtime
evidence rather than worked around by broad unconditional-success stubs.

## Verified E2E scope

The compatibility stack has been exercised end-to-end on the project's
reference systems:

```text
Fedora 44 x86_64
Kubuntu 26.04.1 x86_64
```

The verified user-visible path included:

```text
launcher start
MU startup
GameGuard startup
login
character selection
world entry
audio
```

The full clean E2E reproductions were performed against the installer lineage
whose verified checkpoint SHA256 was:

```text
e2c82048dfd6d5a41bcb5620056a91861bcba0548e0c6d2d5c5230ec05987b7b
```

The current installer SHA256 is:

```text
2daa0ceafe55a12b9c78679505ce3f4dff41ebc8824ad83bca44dca58619a984
```

The difference after the full E2E checkpoint is limited to the Stage 2E private
runtime installation heartbeat.

That heartbeat does not alter the foreground `make install` operation or the
GameGuard compatibility code.

The exact current installer SHA has not been independently rerun through the
entire clean E2E sequence, so the documentation does not claim otherwise.

## Version sensitivity

GameGuard and MU Online are externally updated software.

A later update may change:

```text
GameGuard files
driver behavior
API usage
main.exe
runtime ordering
network behavior
```

A changed game executable hash is therefore not sufficient on its own to prove
a compatibility regression.

Diagnosis should focus on the first behavioral divergence from the verified
startup path.

## Relationship to other documentation

For installation failures and runtime symptoms, see:

```text
TROUBLESHOOTING.md
```

For distribution dependencies and validated distro targets, see:

```text
DISTRO-SUPPORT.md
```

The patch-level implementation details described here are intended to explain
the compatibility model and its boundaries, not to replace those operational
documents.

