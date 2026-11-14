#!/bin/bash
set -euo pipefail

if (( $# > 1 )); then
    printf 'Usage: bash scripts/build-flatc.sh [flatbuffers Git checkout]\n' >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd -P)
version=24.12.23
revision=a2cd1ea3b6d3fee220106b5fed3f7ce8da9eb757
destination="$root/.build/flatbuffers-$version"
mkdir -p "$destination"
scratch=$(mktemp -d "$destination/.prepare.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

if (( $# == 1 )); then
    checkout=$(cd "$1" && pwd -P)
else
    checkout="$scratch/checkout"
    git clone --depth 1 --branch "v$version" https://github.com/google/flatbuffers.git "$checkout"
fi
if [[ "$(git -C "$checkout" rev-parse HEAD)" != "$revision" ]]; then
    printf 'Expected FlatBuffers revision %s (v%s)\n' "$revision" "$version" >&2
    exit 1
fi
mkdir "$scratch/source"
git -C "$checkout" archive "$revision" | tar -xf - -C "$scratch/source"
cmake -S "$scratch/source" -B "$scratch/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DFLATBUFFERS_BUILD_TESTS=OFF
cmake --build "$scratch/build" --target flatc
compiler="$scratch/build/flatc"
if [[ "$("$compiler" --version)" != "flatc version $version" ]]; then
    printf 'Unexpected version from the locally built flatc\n' >&2
    exit 1
fi
mv -f "$compiler" "$destination/flatc"
printf 'Built flatc %s at %s\n' "$version" "$destination/flatc"
