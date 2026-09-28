# MU Online Global on Linux — Manual Installation

> **Historical document — not the current installation procedure.**
>
> This file preserves engineering and manual-reproduction notes from the
> development of the MU Online Linux compatibility layer. Some reference
> environment statements, status labels and TODO items below are historical
> and no longer describe the canonical installer.
>
> For current installation instructions, use
> [`README.md`](../README.md) and the canonical
> [`scripts/install.sh`](../scripts/install.sh).
>
> Current technical documentation:
>
> - [`ARCHITECTURE.md`](ARCHITECTURE.md)
> - [`BUILDING-WINE.md`](BUILDING-WINE.md)
> - [`PATCHES.md`](PATCHES.md)
> - [`GAMEGUARD-COMPAT.md`](GAMEGUARD-COMPAT.md)
> - [`DISTRO-SUPPORT.md`](DISTRO-SUPPORT.md)
> - [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)
>
> The historical body below is intentionally retained for engineering context.
> It must not be treated as an alternative authoritative installation guide.


This document describes the manual installation and reproduction
procedure for running the official MU Online Global client on Linux
with nProtect GameGuard enabled.

The procedure is being written while the complete setup is reproduced
from a clean Wine environment.

## Status legend

    [VERIFIED]  reproduced successfully
    [NEXT]      next clean reproduction step
    [TODO]      not yet reproduced from scratch

Only steps that have actually passed the reproduction procedure are
marked VERIFIED.

---

# 1. Project goal

[VERIFIED]

The goal is to run the official MU Online Global client on Linux using
Wine while preserving the normal nProtect GameGuard startup and driver
lifecycle.

A successful run has already reached:

    MU launcher
      -> main.exe
      -> GameGuard
      -> login
      -> character selection
      -> game world

GameGuard remains enabled throughout this process.

The project modifies Wine compatibility behaviour where required.

It does not require modification of proprietary MU Online or GameGuard
executables.

---

# 2. Anti-cheat integrity boundary

[VERIFIED]

The compatibility work must not:

- disable GameGuard
- bypass GameGuard checks
- patch GameGuard binaries
- patch main.exe
- patch Mu.exe
- fake NtLoadDriver success
- fake GGKernel64 DriverEntry success
- manually inject GGKernel64.sys
- forge GameGuard responses
- hide Linux or Wine processes from GameGuard
- hide modules from GameGuard

GGKernel64.sys is treated as a normal driver supplied and managed by the
official GameGuard installation/update process.

Captured GameGuard binaries used during engineering diagnostics are not
part of the installation procedure and must not be distributed by this
project.

---

# 3. Reference Linux environment

[VERIFIED]

The first confirmed Linux environment is:

    Distribution: Fedora 44
    Architecture: x86_64
    Wine base: Wine 11.6
    Wine architecture: WoW64, i386 + x86_64
    Graphics: WineD3D / OpenGL
    GPU family: AMD Radeon RX 580
    Linux GPU driver: amdgpu

Observed game performance in the successful Fedora run:

    Frame rate: stable 25 FPS
    Global game timing: normal

Measured timing test:

    REAL_SECONDS=60.272
    GAME_SECONDS=60.000
    GAME_TO_REAL_RATIO=0.995485
    GAME_SPEED_PERCENT=99.55%

Therefore no global timer correction is currently required.

The project is intended to support Linux generally.

Fedora 44 is currently the reference distribution, not a permanent
requirement.

Planned package-manager support:

    dnf      Fedora / RHEL family
    apt      Debian / Ubuntu family
    pacman   Arch family
    zypper   openSUSE family

These other distribution families must not be described as VERIFIED
until they have actually been tested.

---

# 4. GameGuard driver architecture

[VERIFIED]

The successful implementation preserves the normal Windows service
control path for loading the GameGuard kernel driver.

Observed architecture:

    Mu.exe
      -> main.exe
      -> GameGuard
      -> GameMon64
      -> NtLoadDriver
      -> Windows Service Control Manager
      -> StartService
      -> services.exe
      -> winedevice.exe
      -> ntoskrnl!ZwLoadDriver()
      -> GGKernel64.sys
      -> DriverEntry

NtLoadDriver must not directly load GGKernel64.sys inside the GameMon64
process.

The Wine compatibility implementation bridges NtLoadDriver to the
normal Service Control Manager workflow.

Relevant Windows service APIs include:

    OpenSCManagerW
    OpenServiceW
    StartServiceW
    ControlService
    CloseServiceHandle

The retained Wine syscall ABI in the reference runtime is:

    NtLoadDriver   = 0x00a1
    NtUnloadDriver = 0x00fa

A GameGuard driver invocation has been observed reaching DriverEntry.

During successful compatibility testing DriverEntry could return:

    STATUS_UNSUCCESSFUL
    0xc0000001

This return value must not be replaced with a fabricated STATUS_SUCCESS.

A known-working environment exhibited the same DriverEntry result while
MU Online and GameGuard continued successfully.

---

# 5. Current reproduction checkpoint

[VERIFIED]

A completely new reproduction prefix has been created:

    ~/.wine-mu-global-repro-v1

It was created using the known-working custom Wine 11.6 runtime.

Immediately after wineboot it was verified that the prefix contained:

    normal Wine prefix structure: yes
    MU Online installation: no
    GGKernel64.sys: no
    GGKernel64 service: no

No registry files, MU files or GameGuard files were copied from the old
working prefix.

Current clean reproduction state:

    [VERIFIED] clean Wine prefix created
    [VERIFIED] no inherited MU installation
    [VERIFIED] no inherited GGKernel64.sys
    [VERIFIED] no inherited GGKernel64 service

    [NEXT] install the official MU Online client into this prefix

---

# 6. Wine compatibility change 1 — NtLoadDriver through SCM

[VERIFIED FUNCTIONALLY]

GameGuard calls NtLoadDriver for its kernel driver.

Stock Wine exposes NtLoadDriver and NtUnloadDriver as NT system calls.
The successful compatibility implementation preserves the existing
Wine kernel-driver architecture instead of loading a .sys file directly
inside the application process.

Relevant Wine components include:

    dlls/ntdll/ntdll.spec
    dlls/ntdll/driver.c
    programs/services
    programs/winedevice
    dlls/ntoskrnl.exe

The required high-level flow is:

    GameMon64
      -> NtLoadDriver
      -> open Service Control Manager
      -> open the requested driver service
      -> StartService
      -> services.exe
      -> winedevice.exe
      -> ntoskrnl!ZwLoadDriver()
      -> driver image
      -> DriverEntry

The compatibility bridge uses the normal Windows SCM API rather than
directly invoking Wine's kernel driver loader from GameMon64.

The implementation uses the service functions:

    OpenSCManagerW
    OpenServiceW
    StartServiceW
    ControlService
    CloseServiceHandle

The working implementation dynamically resolves the service-control
functions through Wine's Windows libraries.

This matters because GameGuard expects its driver to behave like a
Windows service-managed kernel driver.

Directly loading GGKernel64.sys inside GameMon64 would not reproduce
that architecture and is not the solution used by this project.

Reference syscall numbers retained by the working Wine 11.6 build:

    NtLoadDriver   = 0x00a1
    NtUnloadDriver = 0x00fa

Reference SHA256 of the working x86_64 PE ntdll.dll:

    1d7cbea40d6d950ddac396ccae801c41a63bc3b393e458a0287c36b2a9acf5c1

The hash above identifies the development reference binary only.

The public repository will reproduce the change from source instead of
shipping this ntdll.dll.

Planned patch:

    patches/0001-ntdll-ntloaddriver-scm.patch

Current patch status:

    [VERIFIED] behaviour works in the reference Fedora runtime
    [TODO] reduce the source delta against untouched Wine 11.6
    [TODO] export the final clean patch
    [TODO] reproduce the patch from a clean Wine 11.6 source tree

---

# 7. Wine compatibility change 2 — WoW64 PE stack semantics

[VERIFIED FUNCTIONALLY]

MU main.exe is a 32-bit Windows executable running inside the Wine
WoW64 environment.

The executable uses PE stack parameters equivalent to approximately:

    StackReserve = 1 MiB
    StackCommit  = 4 KiB

The successful Wine implementation does not reduce the physical Wine
stack mapping to the PE commit size.

Instead it keeps the normal Wine stack reservation while adjusting the
logical initial StackLimit and PAGE_GUARD position for the special
32-bit WoW64 application stack.

Conceptually:

    full stack reservation stays mapped

    StackBase
        |
        | initial committed application area
        |
    StackLimit
        |
    PAGE_GUARD
        |
        | remaining reserved stack
        |
    lower stack boundary

Only the 32-bit WoW64 application stack uses the PE commit-size
semantics.

Other Wine-created stacks retain the normal Wine behaviour.

The implementation added an internal distinction equivalent to:

    use_commit_size = TRUE

only for the special WoW64 32-bit application stack.

Other stack creation callers use:

    use_commit_size = FALSE

The working behaviour can be summarized as:

    if this is the WoW64 32-bit application stack:
        logical StackLimit = StackBase - PE StackCommit
        place PAGE_GUARD below that limit
        keep the full Wine stack reservation

    otherwise:
        use normal Wine stack behaviour

This change is intentionally narrow.

It must not globally redefine Wine stack allocation semantics.

Existing Wine stack-growth and exception setup mechanisms remain in
use.

The change was required while investigating repeated exceptions in
main.exe, but increasing or relocating the stack alone did not solve
the final world-entry failure.

A separate API-semantics problem in UrlEscapeA was later identified as
the cause of the repeating exception storm.

Reference SHA256 of the working x86_64 Unix ntdll.so:

    beba07499593dc0901486d99d3af892ab963302b168dcb3809533cd20f108fa7

Again, this binary hash is reference information only.

The final project must build the change from Wine source.

Planned patch:

    patches/0002-ntdll-wow64-stack-semantics.patch

Current patch status:

    [VERIFIED] behaviour works in the reference Fedora runtime
    [VERIFIED] special behaviour is limited to the WoW64 app stack
    [TODO] reduce the source delta against untouched Wine 11.6
    [TODO] export the final clean patch
    [TODO] reproduce it in a completely clean build

---

# 8. Wine compatibility change 3 — UrlEscapeA sentinel handling

[VERIFIED]

The final world-entry failure was not caused only by stack allocation
or stack placement.

After the WoW64 stack behaviour had been corrected, main.exe could still
enter a repeating exception sequence.

The recurring exception target was:

    0x6a4e6e69

A historical diagnostic run recorded hundreds of repeated exceptions
before the thread finally exhausted its available stack.

The final failure appeared as:

    virtual_setup_exception stack overflow
    addr 0x6a4e6e69

Investigation traced the exception storm to Wine's ANSI UrlEscapeA
handling.

Relevant Wine source file:

    dlls/kernelbase/path.c

The important condition concerns the caller-provided output-length
value.

The value:

    ~0u

must not be treated as a normal writable buffer capacity.

The working implementation explicitly handles this sentinel before
attempting the ANSI conversion.

The required logic is:

    if (hr == S_OK)
    {
        RtlUnicodeToMultiByteSize(&lenA, escapedW,
                                  lenW * sizeof(WCHAR));

        if (*escaped_len == ~0u)
        {
            *escaped_len = lenA + 1;
            hr = E_INVALIDARG;
        }
        else if (*escaped_len > lenA)
        {
            RtlUnicodeToMultiByteN(
                escaped,
                *escaped_len - 1,
                &lenA,
                escapedW,
                lenW * sizeof(WCHAR));

            escaped[lenA] = 0;
            *escaped_len = lenA;
        }
        else
        {
            *escaped_len = lenA + 1;
            hr = E_POINTER;
        }
    }

The essential compatibility case is:

    *escaped_len == ~0u

Without this handling, the invalid capacity can reach the conversion
path and trigger the repeating exception behaviour observed in
MU main.exe.

After applying the working UrlEscapeA semantics, the successful world
test reported:

    STACK_OVERFLOW_COUNT=0
    TARGET_6A4E6E69_COUNT=0

MU then entered the game world successfully.

Reference SHA256 of the working path.c:

    79c94874e4c8bb492987c37c289f77405ec0be9ddb7038eb5f4ea310c8295f74

Reference SHA256 of the working PE32 kernelbase.dll:

    31fe70a408017240a86cf6b06b93c8ec556d856a66b370162746a3d056ba2aa5

Reference SHA256 of the unchanged x86_64 kernelbase.dll:

    1998fa5db6f84391f27b237926e15d1f39fe04dd3fc66d903489d5102c8afed0

These hashes identify the development reference build only.

The public repository must reproduce this behaviour from Wine source
rather than distribute kernelbase.dll.

Planned patch:

    patches/0003-kernelbase-urlescape-sentinel.patch

Current patch status:

    [VERIFIED] exact source semantics identified
    [VERIFIED] working Fedora runtime enters the game world
    [VERIFIED] previous 0x6a4e6e69 exception storm is absent
    [TODO] export the exact patch against untouched Wine 11.6
    [TODO] reproduce it in a completely clean Wine build

---

# 9. Wine compatibility change 4 — ntoskrnl GameGuard compatibility

[VERIFIED]

The clean ntoskrnl compatibility patch is now stored as:

    patches/0004-ntoskrnl-gameguard-compat.patch

The patch changes only:

    dlls/ntoskrnl.exe/ntoskrnl.c
    dlls/ntoskrnl.exe/ntoskrnl.exe.spec

The final public patch contains the required compatibility work for:

    IoCreateDeviceSecure
    SeCaptureSecurityDescriptor
    KeGetCurrentIrql

It does not contain the temporary GameGuard-specific diagnostic probes,
sleep delays, stack probes or hard-coded diagnostic addresses used during
engineering.

Reference SHA256 of the verified patch:

    d40695dcc32b3f2f5343e4bf1eef5ae7a212da4fdb0f454209f0c1d833721399

Reference SHA256 of the clean x86_64 ntoskrnl.exe produced during the
successful functional test:

    a3f8eb21d824638a4c567b5a7182ae00633795815c180ef865f24e27af5a06a7

The clean ntoskrnl test successfully reached:

    Mu.exe
      -> main.exe
      -> GameGuard
      -> kernel-driver service path
      -> DriverEntry
      -> login
      -> character selection
      -> world

During the successful world test GameGuard remained enabled and
GGKernel64.sys did not require any manual restoration.

Current patch status:

    [VERIFIED] clean patch generated from pristine Wine 11.6 source
    [VERIFIED] diagnostic GameGuard probes removed
    [VERIFIED] GameGuard starts normally
    [VERIFIED] MU reaches the game world
    [VERIFIED] no manual GGKernel64.sys restoration required

---

# 10. Audio build dependencies

[VERIFIED ON FEDORA 44]

The first custom Wine 11.6 build was created without Wine's PulseAudio and
ALSA backends because the development packages were missing.

The resulting Wine configuration disabled:

    dlls/winepulse.drv
    dlls/winealsa.drv

and MU reported:

    No driver from L"pulse,alsa,oss,coreaudio" could be initialized.

For the Fedora 44 WoW64 reference build the following development packages
are required for both 64-bit and 32-bit development environments:

    pulseaudio-libs-devel.x86_64
    pulseaudio-libs-devel.i686
    alsa-lib-devel.x86_64
    alsa-lib-devel.i686

After installing these packages, Wine 11.6 configure successfully detected:

    PulseAudio: yes
    ALSA: yes

The resulting build variables included:

    PULSE_LIBS = -lpulse -pthread
    ALSA_LIBS = -lasound

and neither winepulse.drv nor winealsa.drv remained in DISABLED_SUBDIRS.

The Unix-side backend modules produced by the current WoW64 build are:

    lib/wine/x86_64-unix/winepulse.so
    lib/wine/x86_64-unix/winealsa.so

Reference SHA256 values from the successful Fedora test:

    winepulse.so
    22a98781ae536f949df924b178528ea435ec58c12f414d00e24a7ebbcf803931

    winealsa.so
    bceffb7e90c2e9616f50fa470c98fdfe9d8171cf81cd52426b54b2366289dbaa

With these backends installed in the isolated Wine runtime:

    [VERIFIED] MMDevAPI initialized without the no-driver error
    [VERIFIED] MU Online produced normal game audio
    [VERIFIED] clean ntoskrnl remained unchanged
    [VERIFIED] GameGuard continued working
    [VERIFIED] MU continued reaching the game world

The Fedora dependency names above are verified only for Fedora 44.

Equivalent package names for Debian/Ubuntu, Arch and openSUSE must be
verified on those distributions before they are marked as supported.

