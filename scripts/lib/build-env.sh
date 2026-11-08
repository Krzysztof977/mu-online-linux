#!/usr/bin/env bash
# v0.2.0 experimental, distribution-independent build environment validator.
# Sourcing this file has no side effects. Running mu_check_build_environment
# never installs packages, requires root, or builds Wine.

mu_env_issue() {
    local kind="$1" name="$2"
    MU_ENV_MISSING+=("$kind:$name")
    printf 'MISSING  %-13s %s\n' "$kind" "$name"
}

mu_env_pass() {
    printf 'OK       %-13s %s\n' "$1" "$2"
}

mu_env_cc() {
    local name="$1" source="$2" output="$3" pc_flags="$4"
    shift 4
    local -a flags=()
    read -r -a flags <<< "$pc_flags"
    gcc "$@" "$source" "${flags[@]}" -o "$output" \
        >"$MU_ENV_WORK/compile.log" 2>&1
}

mu_env_native_module() {
    local name="$1" header="$2" expression="$3"
    local flags
    if ! pkg-config --exists "$name"; then
        mu_env_issue pkgconfig "$name"
        return 1
    fi
    flags="$(pkg-config --cflags --libs "$name")" || {
        mu_env_issue pkgconfig "$name"
        return 1
    }
    if [[ "$name" == freetype2 ]]; then
        printf '#include <ft2build.h>\n#include FT_FREETYPE_H\nint main(void) { %s; return 0; }\n' \
            "$expression" > "$MU_ENV_WORK/module.c"
    else
        printf '#include <%s>\nint main(void) { %s; return 0; }\n' \
            "$header" "$expression" > "$MU_ENV_WORK/module.c"
    fi
    if ! mu_env_cc "$name" "$MU_ENV_WORK/module.c" \
         "$MU_ENV_WORK/module" "$flags"; then
        mu_env_issue link64 "$name"
        # Include the actual compiler diagnostic, not just the last caret line.
        sed -n '1,8{s/^/DETAIL   /;p;}' "$MU_ENV_WORK/compile.log"
        return 1
    fi
    mu_env_pass link64 "$name"
}

mu_env_audio32() {
    local dir flags
    local -a dirs=(
        /usr/lib32/pkgconfig
        /usr/lib/i386-linux-gnu/pkgconfig
        /usr/lib/pkgconfig
    )
    dir=""
    for candidate in "${dirs[@]}"; do
        if [[ -f "$candidate/libpulse.pc" &&
              -f "$candidate/alsa.pc" ]]; then
            dir="$candidate"
            break
        fi
    done
    if [[ -z "$dir" ]]; then
        mu_env_issue pkgconfig32 "libpulse+alsa"
        return 1
    fi
    if ! flags="$(PKG_CONFIG_LIBDIR="$dir:/usr/share/pkgconfig" \
        pkg-config --cflags --libs libpulse alsa)"; then
        mu_env_issue pkgconfig32 "libpulse+alsa"
        return 1
    fi

    cat > "$MU_ENV_WORK/audio32.c" <<'EOF'
#include <pulse/pulseaudio.h>
#include <alsa/asoundlib.h>
int main(void) {
    pa_mainloop *p = pa_mainloop_new();
    if (p) pa_mainloop_free(p);
    return snd_asoundlib_version() == 0;
}
EOF
    local -a flags_array=()
    read -r -a flags_array <<< "$flags"
    if ! gcc -m32 "$MU_ENV_WORK/audio32.c" \
        -L"${dir%/pkgconfig}" \
        "${flags_array[@]}" -o "$MU_ENV_WORK/audio32" \
        >"$MU_ENV_WORK/compile.log" 2>&1; then
        mu_env_issue link32 "libpulse+alsa"
        # Include the actual compiler diagnostic, not just the last caret line.
        sed -n '1,8{s/^/DETAIL   /;p;}' "$MU_ENV_WORK/compile.log"
        return 1
    fi
    if ! file -b "$MU_ENV_WORK/audio32" | grep -q 'ELF 32-bit'; then
        mu_env_issue abi32 "audio ELF"
        return 1
    fi
    mu_env_pass link32 "libpulse+alsa ($dir)"
}

mu_env_mingw() {
    local arch="$1" expected="$2"
    local cc="${arch}-w64-mingw32-gcc"
    local ld="${arch}-w64-mingw32-ld"
    if ! command -v "$cc" >/dev/null 2>&1; then
        mu_env_issue command "$cc"
        return 1
    fi
    if ! command -v "$ld" >/dev/null 2>&1; then
        mu_env_issue command "$ld"
        return 1
    fi
    cat >"$MU_ENV_WORK/windows.c" <<'EOF'
#include <windows.h>
int main(void) { return GetTickCount() == 0; }
EOF
    if ! "$cc" "$MU_ENV_WORK/windows.c" \
        -o "$MU_ENV_WORK/windows-${arch}.exe" \
        >"$MU_ENV_WORK/compile.log" 2>&1; then
        mu_env_issue mingw "$arch"
        # Include the actual compiler diagnostic, not just the last caret line.
        sed -n '1,8{s/^/DETAIL   /;p;}' "$MU_ENV_WORK/compile.log"
        return 1
    fi
    if ! file -b "$MU_ENV_WORK/windows-${arch}.exe" | grep -Fq "$expected"; then
        mu_env_issue mingwabi "$arch"
        return 1
    fi
    mu_env_pass mingw "$arch ($expected)"
}

mu_check_build_environment() {
    local cmd mod header expr
    local -a required=(
        awk bison curl file flex g++ gcc make msgfmt patch
        python3 pkg-config sha256sum tar xz cmp find grep perl
        readlink sed stat
    )
    MU_ENV_MISSING=()
    MU_BUILD_ENV_STATUS="missing"

    printf '=== BUILD ENVIRONMENT: REQUIRED TOOLS ===\n'
    local commands_ready=1
    for cmd in "${required[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            mu_env_pass command "$cmd"
        else
            mu_env_issue command "$cmd"
            commands_ready=0
        fi
    done

    # Never begin compile probes if the tools to run them are missing.
    if (( ! commands_ready )); then
        printf 'BUILD_ENV_MISSING_COUNT=%d\n' "${#MU_ENV_MISSING[@]}"
        printf 'BUILD_ENV_STATUS=missing\n'
        return 1
    fi

    MU_ENV_WORK="$(mktemp -d)" || {
        mu_env_issue environment "mktemp"
        printf 'BUILD_ENV_STATUS=missing\n'
        return 1
    }
    printf '\n=== BUILD ENVIRONMENT: CROSS COMPILERS ===\n'
    mu_env_mingw i686 'PE32 executable' || :
    mu_env_mingw x86_64 'PE32+ executable' || :

    printf '\n=== BUILD ENVIRONMENT: NATIVE HEADERS AND LINKING ===\n'
    # Each probe must include a real symbol, so --as-needed cannot bypass
    # resolving the library. The probe binaries are never executed.
    mu_env_native_module freetype2 ft2build.h \
        'FT_Library lib; (void)FT_Init_FreeType(&lib)' || :
    mu_env_native_module gnutls gnutls/gnutls.h \
        '(void)gnutls_check_version(0)' || :
    mu_env_native_module x11 X11/Xlib.h \
        '(void)XOpenDisplay(0)' || :
    mu_env_native_module xcursor X11/Xcursor/Xcursor.h \
        '(void)XcursorLibraryLoadCursor(0, "xterm")' || :
    mu_env_native_module xi X11/extensions/XInput2.h \
        'int a=2,b=0; (void)XIQueryVersion(0,&a,&b)' || :
    mu_env_native_module xrandr X11/extensions/Xrandr.h \
        'int a=0,b=0; (void)XRRQueryVersion(0,&a,&b)' || :
    mu_env_native_module wayland-client wayland-client.h \
        '(void)wl_display_connect(0)' || :
    mu_env_native_module egl EGL/egl.h \
        '(void)eglGetDisplay(EGL_DEFAULT_DISPLAY)' || :
    mu_env_native_module gbm gbm.h \
        '(void)gbm_create_device(-1)' || :
    mu_env_native_module vulkan vulkan/vulkan.h \
        'uint32_t n=0; (void)vkEnumerateInstanceVersion(&n)' || :
    mu_env_native_module libpulse pulse/pulseaudio.h \
        '(void)pa_mainloop_new()' || :
    mu_env_native_module alsa alsa/asoundlib.h \
        '(void)snd_asoundlib_version()' || :

    printf '\n=== BUILD ENVIRONMENT: 32-BIT AUDIO LINK/ABI ===\n'
    mu_env_audio32 || :

    rm -rf -- "$MU_ENV_WORK"
    unset MU_ENV_WORK

    printf '\nBUILD_ENV_MISSING_COUNT=%d\n' "${#MU_ENV_MISSING[@]}"
    if (( ${#MU_ENV_MISSING[@]} == 0 )); then
        MU_BUILD_ENV_STATUS="ready"
        printf 'BUILD_ENV_STATUS=ready\n'
        printf 'V020_BUILD_ENV_PREFLIGHT_PASS=True\n'
        return 0
    fi
    printf 'BUILD_ENV_STATUS=missing\n'
    printf 'V020_BUILD_ENV_PREFLIGHT_INCOMPLETE=True\n'
    return 1
}
