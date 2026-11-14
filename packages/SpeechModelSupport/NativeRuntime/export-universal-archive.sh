#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 || ( $# -eq 4 && "$4" != "--asan" ) ]]; then
    printf 'Usage: %s ARM64_BUILD X86_64_BUILD OUTPUT_DIRECTORY [--asan]\n' "$0" >&2
    exit 2
fi

runtime=$(cd "$(dirname "$0")" && pwd -P)
requestedSanitizer=OFF
if [[ "${4:-}" == "--asan" ]]; then
    requestedSanitizer=ON
fi

fail() {
    printf '%s\n' "$1" >&2
    exit 2
}

outputParent=$(cd -- "$(dirname -- "$3")" && pwd -P)
output="$outputParent/$(basename -- "$3")"
[[ ! -e "$output" && ! -L "$output" ]] || fail "Output directory already exists: $output"
scratch=$(mktemp -d "$outputParent/.gergram-whisper-export.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

cache_value() {
    /usr/bin/sed -n "s/^$1:[^=]*=//p" "$2"
}

archive_metadata() {
    xcrun otool -arch "$1" -l "$2" | /usr/bin/awk '
        /\):$/ { members++ }
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { versions++ }
        $1 == "platform" && $2 == "1" { macOS++ }
        $1 == "minos" { if (minimum != "" && minimum != $2) exit 1; minimum = $2; minimumCommands++ }
        $1 == "sdk" { if (sdk != "" && sdk != $2) exit 1; sdk = $2; sdkCommands++ }
        END {
            if (members == 0 || members != versions || members != macOS || members != minimumCommands || members != sdkCommands || sdk == "n/a") exit 1
            print minimum, sdk
        }
    '
}

build_slice() {
    local architecture="$1" build="$2" cache deployment license expected archive metadata symbolMode
    cache="$build/CMakeCache.txt"
    [[ -f "$cache" && "$(cache_value CMAKE_HOME_DIRECTORY "$cache")" == "$runtime" ]] \
        || fail "Configure the Gergram native runtime first: $build"
    [[ "$(cache_value CMAKE_OSX_ARCHITECTURES "$cache")" == "$architecture" ]] \
        || fail "Expected $architecture CMake build: $build"
    [[ "$(cache_value GERGRAM_WHISPER_ASAN "$cache")" == "$requestedSanitizer" ]] \
        || fail "Expected GERGRAM_WHISPER_ASAN=$requestedSanitizer: $build"

    deployment=$(cache_value CMAKE_OSX_DEPLOYMENT_TARGET "$cache")
    [[ "$deployment" =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$ && "${deployment%%.*}" -ge 11 ]] \
        || fail "Set an explicit macOS deployment target of 11.0 or later: $build"
    if [[ "$deployment" == *.*.0 ]]; then
        deployment=${deployment%.0}
    fi

    license="$build/verified-whisper-source/LICENSE"
    [[ -f "$license" && "$(git hash-object --no-filters -- "$license")" == "$pinnedLicense" ]] \
        || fail "Missing or modified pinned whisper.cpp license: $build"

    local archives=(
        "$build/libGergramWhisperRuntime.a"
        "$build/whisper/src/libwhisper.a"
        "$build/whisper/ggml/src/libggml.a"
        "$build/whisper/ggml/src/libggml-cpu.a"
        "$build/whisper/ggml/src/libggml-base.a"
    )
    for archive in "${archives[@]}"; do
        [[ -f "$archive" && "$(xcrun lipo -archs "$archive")" == "$architecture" ]] \
            || fail "Missing or mismatched $architecture archive: $archive"
        metadata=$(archive_metadata "$architecture" "$archive") \
            || fail "Invalid or mixed macOS build metadata: $archive"
        [[ "${metadata%% *}" == "$deployment" ]] \
            || fail "Archive deployment differs from CMake: $archive"
        symbolMode=$(xcrun nm -u "$archive" 2> /dev/null | /usr/bin/awk '$NF == "___asan_init" { enabled = 1 } END { print enabled ? "ON" : "OFF" }') \
            || fail "Could not inspect archive sanitizer symbols: $archive"
        [[ "$symbolMode" == "$requestedSanitizer" ]] || fail "Archive sanitizer differs from CMake: $archive"
        expected=${expected:-$metadata}
        [[ "$metadata" == "$expected" ]] || fail "Archives were built for different macOS SDKs: $build"
    done

    xcrun libtool -static -D -no_warning_for_no_symbols -o "$scratch/$architecture.a" "${archives[@]}" \
        || fail "Could not merge the $architecture archives."
    printf '%s\n' "$expected"
}

armBuild=$(cd "$1" && pwd -P)
intelBuild=$(cd "$2" && pwd -P)
pinnedLicense=$(/usr/bin/awk '$2 == "LICENSE" { print $1 }' "$runtime/WhisperSourceBlobs.txt")
armMetadata=$(build_slice arm64 "$armBuild")
intelMetadata=$(build_slice x86_64 "$intelBuild")
[[ "$armMetadata" == "$intelMetadata" ]] || fail 'Build both slices for the same macOS deployment target and SDK.'

mkdir -p "$scratch/export/include"
xcrun lipo -create "$scratch/arm64.a" "$scratch/x86_64.a" -output "$scratch/export/libGergramWhisperRuntime.a"
for architecture in arm64 x86_64; do
    xcrun lipo -verify_arch "$architecture" "$scratch/export/libGergramWhisperRuntime.a"
done
cp "$runtime/WhisperRuntime.h" "$runtime/module.modulemap" "$scratch/export/include/"
cp "$armBuild/verified-whisper-source/LICENSE" "$scratch/export/LICENSE"

# Publish the completed export with exact-path, no-replace semantics on Darwin.
xcrun clang -x c -o "$scratch/publish" - <<'C'
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    if (renamex_np(argv[1], argv[2], RENAME_EXCL) == 0) return 0;
    perror(argv[2]);
    return 1;
}
C
"$scratch/publish" "$scratch/export" "$output"
printf 'Exported arm64 and x86_64 for macOS %s (SDK %s, ASan %s) to %s\n' \
    "${armMetadata%% *}" "${armMetadata#* }" "$requestedSanitizer" "$output"
