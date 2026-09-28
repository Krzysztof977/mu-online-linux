# Wine Patch Set

This document describes the four source patches carried by the project for its
private Wine 11.6 runtime.

The patches are part of the verified source inputs. Their filenames and SHA256
digests are pinned and should be treated as integrity-sensitive build inputs.

The project does not patch MU Online or GameGuard binaries.

## Patch inventory

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

Do not replace a patch with another revision while keeping its old expected
digest.

A patch-content change is a source change and requires a new digest and new
validation.

## Patch 0001: ntdll NtLoadDriver and SCM compatibility

File:

```text
patches/0001-ntdll-ntloaddriver-scm.patch
```

SHA256:

```text
128398b6cc9a8be12771df8636e6ab5db96dc68c2ed4dc275045211354e79ab8
```

Primary purpose:

```text
provide NtLoadDriver / NtUnloadDriver behavior through Wine SCM
```

### Files modified by patch 0001

```text
dlls/ntdll/Makefile.in
dlls/ntdll/driver.c
dlls/ntdll/ntsyscalls.h
dlls/ntdll/signal_i386.c
dlls/ntdll/signal_x86_64.c
tools/make_specfiles
```

`dlls/ntdll/driver.c` is added by the patch.

### Driver service path handling

The implementation accepts service registry paths below:

```text
\Registry\Machine\System\CurrentControlSet\Services\
```

It validates the input and extracts the service name rather than accepting an
arbitrary registry path as a driver service.

### SCM interface

The implementation resolves these functions from `sechost.dll`:

```text
OpenSCManagerW
OpenServiceW
StartServiceW
ControlService
CloseServiceHandle
```

A load request starts the corresponding Wine service with:

```text
StartServiceW
```

An unload request uses:

```text
ControlService
SERVICE_CONTROL_STOP
```

This delegates service operation to Wine's service infrastructure.

The patch comment explicitly states that kernel driver images continue to be
hosted by:

```text
winedevice
```

### Error semantics

Patch 0001 maps relevant SCM errors to NTSTATUS values.

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

An unmapped service failure becomes:

```text
STATUS_UNSUCCESSFUL
```

The patch therefore does not turn all driver-service operations into
unconditional success.

### Syscall integration

Patch 0001 also changes generated syscall handling for:

```text
NtLoadDriver
NtUnloadDriver
```

in both i386 and x86_64 syscall definitions.

The architecture-specific signal sources avoid generating conflicting syscall
wrappers for these implementations.

`tools/make_specfiles` is updated so regenerated syscall metadata retains the
same special handling.

## Patch 0002: WoW64 stack semantics

File:

```text
patches/0002-ntdll-wow64-stack-semantics.patch
```

SHA256:

```text
507dcf28948909a3d869b58f5ff1aa1272a1c6b6abeb2d42e6350c6ae9cad8a0
```

Primary purpose:

```text
adjust StackLimit and guard-page semantics for the 32-bit WoW64 application stack
```

### Files modified by patch 0002

```text
dlls/ntdll/unix/thread.c
dlls/ntdll/unix/unix_private.h
dlls/ntdll/unix/virtual.c
```

### Allocation interface change

The patch extends:

```text
virtual_alloc_thread_stack
```

with an additional boolean parameter:

```text
use_commit_size
```

The special behavior is selected only for the 32-bit application stack in the
WoW64 path.

Other stack allocations pass:

```text
use_commit_size = FALSE
```

including the kernel, 64-bit, emulator and native stack paths modified by the
patch.

### 32-bit WoW64 behavior

For the selected path the patch calculates:

```text
stack_base  = view base + view size
stack_limit = stack_base - commit_size
guard       = stack_limit - host_page_size
```

The TEB receives:

```text
StackLimit = StackBase - commit_size
```

and the guard page is positioned immediately below that boundary.

The patch explicitly keeps the full stack mapping committed as in stock Wine.

This is a targeted semantic adjustment, not a general replacement of Wine's
thread-stack allocation model.

## Patch 0003: kernelbase UrlEscape sentinel handling

File:

```text
patches/0003-kernelbase-urlescape-sentinel.patch
```

SHA256:

```text
98478fac80966bffac650a76e870ba1a39a809eb5d20d783dd8486cb9b628572
```

Primary purpose:

```text
handle the ~0u escaped-length sentinel explicitly in the ANSI UrlEscape path
```

### File modified by patch 0003

```text
dlls/kernelbase/path.c
```

The patch is intentionally small.

When:

```text
*escaped_len == ~0u
```

the patched path sets:

```text
*escaped_len = lenA + 1
```

and returns:

```text
E_INVALIDARG
```

For ordinary output-buffer lengths greater than the converted string length,
the existing ANSI conversion behavior remains in place.

## Patch 0004: ntoskrnl compatibility

File:

```text
patches/0004-ntoskrnl-gameguard-compat.patch
```

SHA256:

```text
d40695dcc32b3f2f5343e4bf1eef5ae7a212da4fdb0f454209f0c1d833721399
```

Primary purpose:

```text
add bounded ntoskrnl behavior used by the observed driver path
```

### Files modified by patch 0004

```text
dlls/ntoskrnl.exe/ntoskrnl.c
dlls/ntoskrnl.exe/ntoskrnl.exe.spec
```

The patch affects three principal compatibility areas:

```text
IoCreateDeviceSecure
SeCaptureSecurityDescriptor
KeGetCurrentIrql
```

## IoCreateDeviceSecure changes

The stock implementation at the patched location was a semi-stub that delegated
directly to:

```text
IoCreateDevice
```

Patch 0004 adds partial security-descriptor behavior.

When an SDDL descriptor is supplied, it:

```text
validates the UNICODE_STRING length
creates a NUL-terminated copy
parses the SDDL
determines SECURITY_INFORMATION flags
determines required access rights
creates the device
opens the device object
applies the security descriptor
```

The implementation uses:

```text
ConvertStringSecurityDescriptorToSecurityDescriptorW
ObOpenObjectByPointer
NtSetSecurityObject
```

If security application fails after device creation, the patch removes the
created device with:

```text
IoDeleteDevice
```

and clears the returned device pointer.

### IoCreateDeviceSecure boundary

The patch explicitly identifies its implementation as partial.

This behavior is not implemented:

```text
DeviceClassGuid registry override
```

The patch does not silently claim complete `IoCreateDeviceSecure`
compatibility.

## SeCaptureSecurityDescriptor changes

The Wine stub for:

```text
SeCaptureSecurityDescriptor
```

is replaced with an implementation supporting the self-relative descriptor
path required by the observed workload.

The implementation validates descriptor revision and validity.

For the capture path, a supported self-relative descriptor is copied using:

```text
RtlLengthSecurityDescriptor
ExAllocatePoolWithTag
```

### SeCaptureSecurityDescriptor boundary

The patch deliberately does not implement arbitrary conversion of absolute
security descriptors.

For that unsupported path it returns:

```text
STATUS_NOT_IMPLEMENTED
```

The patch comment records that the observed WDMSEC path supplies an already
self-relative descriptor.

## KeGetCurrentIrql change

Patch 0004 adds the x86_64 export:

```text
KeGetCurrentIrql
```

The compatibility implementation currently returns:

```text
0
```

corresponding to passive IRQL for the supported path.

This is a narrow implementation detail and is not an unconditional-success
return for `NtLoadDriver`, `DriverEntry`, or GameGuard as a whole.

## Patch-set boundaries

The four patches change Wine source code only.

They do not:

```text
patch Mu.exe
patch main.exe
patch GameGuard binaries
bundle GGKernel64.sys
copy GGKernel64.sys
disable GameGuard
hide processes
hide modules
force NtLoadDriver to succeed
force DriverEntry to succeed
```

The patches implement or adjust Windows compatibility behavior in the private
Wine runtime.

Unsupported paths continue to return meaningful errors where implemented.

## Integrity policy

Each patch is tied to an expected SHA256 digest.

A patch must not be accepted solely because:

```text
its filename is unchanged
it still applies cleanly
Wine still compiles
MU still starts
```

A content change requires deliberate review and an updated integrity value.

This prevents an unnoticed local patch edit from becoming part of a supposedly
reproducible runtime.

## Relationship to Wine source

The patch set is maintained against the project's pinned Wine source:

```text
Wine 11.6
```

The source archive SHA256 is:

```text
d49d166975478f609e6a9cdbda0a07c65a3b795e061fc454d3f1034c828d19e0
```

A later Wine version may have different source structure or upstream behavior.

A patch applying with offsets or fuzz to another Wine version is not sufficient
evidence that the resulting semantics are equivalent.

## Relationship to GameGuard compatibility documentation

For the complete runtime model, service-record preparation, normal
`GGKernel64.sys` lifecycle, prelaunch invariants and no-bypass boundaries, see:

```text
GAMEGUARD-COMPAT.md
```

For operational failure diagnosis, see:

```text
TROUBLESHOOTING.md
```

This document focuses on the source patch set itself.

