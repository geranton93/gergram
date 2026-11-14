#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != "--asan" ) ]]; then
    printf 'Usage: %s CMAKE_BUILD_DIRECTORY [--asan]\n' "$0" >&2
    exit 2
fi

runtime=$(cd "$(dirname "$0")" && pwd)
build=$(cd "$1" && pwd)
cache="$build/CMakeCache.txt"
if [[ ! -f "$cache" ]]; then
    printf 'Configure and build the native runtime first: %s\n' "$cache" >&2
    exit 2
fi

cache_value() {
    /usr/bin/sed -n "s/^$1:[^=]*=//p" "$cache"
}

architecture=$(cache_value CMAKE_OSX_ARCHITECTURES)
deployment=$(cache_value CMAKE_OSX_DEPLOYMENT_TARGET)
sanitizer=$(cache_value GERGRAM_WHISPER_ASAN)
if [[ ! "$architecture" =~ ^(arm64|x86_64)$ || ! "$deployment" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    printf 'Reconfigure with one macOS architecture and an explicit deployment target.\n' >&2
    exit 2
fi

flags=(-target "$architecture-apple-macosx$deployment")
case "$sanitizer" in
    ON) flags+=(-sanitize=address) ;;
    OFF)
        if [[ "${2:-}" == "--asan" ]]; then
            printf 'The native build has Address Sanitizer disabled. Reconfigure it with -DGERGRAM_WHISPER_ASAN=ON.\n' >&2
            exit 2
        fi
        ;;
    *)
        printf 'Reconfigure the native build with GERGRAM_WHISPER_ASAN set to ON or OFF.\n' >&2
        exit 2
        ;;
esac

if ! /usr/bin/arch "-$architecture" /usr/bin/true > /dev/null 2>&1; then
    printf 'This Mac cannot execute %s binaries. Use a compatible Mac or Rosetta for Intel binaries on Apple Silicon.\n' "$architecture" >&2
    exit 2
fi

archives=(
    "$build/libGergramWhisperRuntime.a"
    "$build/whisper/src/libwhisper.a"
    "$build/whisper/ggml/src/libggml.a"
    "$build/whisper/ggml/src/libggml-cpu.a"
    "$build/whisper/ggml/src/libggml-base.a"
)
for archive in "${archives[@]}"; do
    if ! xcrun lipo -verify_arch "$architecture" "$archive" > /dev/null 2>&1; then
        printf 'Missing native archive or %s slice: %s\n' "$architecture" "$archive" >&2
        exit 2
    fi
done

swiftFixture=$(mktemp -d)
trap 'rm -rf "$swiftFixture"' EXIT

cd "$swiftFixture"
export CLANG_MODULE_CACHE_PATH="$swiftFixture/cache"
xcrun swiftc -emit-library -emit-module -enable-testing -module-name SpeechModelSupport \
    "${flags[@]}" "$runtime/../Sources/SpeechModelSupport/"*.swift
mkdir executable
cp "$runtime/SwiftCacheFixture.swift" executable/main.swift
xcrun swiftc -I . -I "$runtime" -L . -lSpeechModelSupport -lc++ \
    "${flags[@]}" executable/main.swift "$runtime/WhisperNativeTranscription.swift" "${archives[@]}" \
    -Xlinker -rpath -Xlinker "$swiftFixture" -o verify-swift
/usr/bin/arch "-$architecture" ./verify-swift "$build/verified-whisper-source/models/for-tests-ggml-tiny.bin"
