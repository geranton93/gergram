#!/bin/sh
set -eu

package_dir=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/gergram-message-shot.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/Sources/ChatUI" "$fixture/Tests/ChatUITests"
for package in ColorPalette Colors Strings; do
    ln -s "$package_dir/../$package" "$fixture/$package"
done
for source in MessageShotOptions.swift MessageShotRenderer.swift; do
    ln -s "$package_dir/Sources/ChatUI/$source" "$fixture/Sources/ChatUI/$source"
done
ln -s "$package_dir/Tests/ChatUITests/MessageShotTests.swift" "$fixture/Tests/ChatUITests/MessageShotTests.swift"

cat > "$fixture/Package.swift" <<'SWIFT'
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MessageShotFixture",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(path: "ColorPalette")],
    targets: [
        .target(name: "ChatUI", dependencies: ["ColorPalette"]),
        .testTarget(name: "ChatUITests", dependencies: ["ChatUI", "ColorPalette"])
    ]
)
SWIFT

CLANG_MODULE_CACHE_PATH="$fixture/clang-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$fixture/swift-cache" \
    xcrun swift test --package-path "$fixture" --manifest-cache none --filter MessageShotTests "$@"
