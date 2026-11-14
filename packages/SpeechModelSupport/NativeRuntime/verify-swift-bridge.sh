#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != "--asan" ) ]]; then
    printf 'Usage: %s CMAKE_BUILD_DIRECTORY [--asan]\n' "$0" >&2
    exit 2
fi

runtime=$(cd "$(dirname "$0")" && pwd)
build=$(cd "$1" && pwd)
swiftFixture=$(mktemp -d)
trap 'rm -rf "$swiftFixture"' EXIT
flags=()
if [[ "${2:-}" == "--asan" ]]; then
    flags+=(-sanitize=address)
fi

cd "$swiftFixture"
export CLANG_MODULE_CACHE_PATH="$swiftFixture/cache"
xcrun swiftc -emit-library -emit-module -enable-testing -module-name SpeechModelSupport \
    "${flags[@]}" "$runtime/../Sources/SpeechModelSupport/"*.swift
xcrun swiftc -I . -I "$runtime" -L . -lSpeechModelSupport -lc++ \
    "${flags[@]}" "$runtime/SwiftCacheFixture.swift" "$build/libGergramWhisperRuntime.a" \
    "$build/whisper/src/libwhisper.a" "$build/whisper/ggml/src/libggml.a" \
    "$build/whisper/ggml/src/libggml-cpu.a" "$build/whisper/ggml/src/libggml-base.a" \
    -Xlinker -rpath -Xlinker "$swiftFixture" -o verify-swift
./verify-swift "$build/verified-whisper-source/models/for-tests-ggml-tiny.bin"
