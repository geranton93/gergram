#!/bin/sh
set -eu

package_dir=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/gergram-direct-read-ahead.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/Sources/TelegramMedia" "$fixture/Tests/TelegramMediaTests"
ln -s "$package_dir/Sources/DirectMediaReadAhead.swift" "$fixture/Sources/TelegramMedia/DirectMediaReadAhead.swift"
ln -s "$package_dir/Tests/TelegramMediaTests/DirectMediaReadAheadTests.swift" "$fixture/Tests/TelegramMediaTests/DirectMediaReadAheadTests.swift"

cat > "$fixture/Package.swift" <<'SWIFT'
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "DirectMediaReadAheadFixture",
    targets: [
        .target(name: "TelegramMedia"),
        .testTarget(name: "TelegramMediaTests", dependencies: ["TelegramMedia"])
    ]
)
SWIFT

CLANG_MODULE_CACHE_PATH="$fixture/clang-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$fixture/swift-cache" \
    xcrun swift test --package-path "$fixture" --manifest-cache none --filter DirectMediaReadAheadTests "$@"
