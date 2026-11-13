import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description="Test the edited indicator preference with the native signal implementation.")
parser.add_argument("--signal-kit", type=Path, default=root / "submodules/telegram-ios/submodules/SSignalKit")
args = parser.parse_args()
signal_kit = args.signal_kit.resolve()
if not (signal_kit / "Package.swift").is_file():
    parser.error("Missing SSignalKit package. Initialize the telegram-ios submodule or supply --signal-kit.")

with tempfile.TemporaryDirectory(prefix="gergram-chat-edited-indicator-") as directory:
    workspace = Path(directory)
    source = workspace / "Sources"
    tests = workspace / "Tests"
    source.mkdir()
    tests.mkdir()
    shutil.copy(root / "packages/InAppSettings/Sources/InAppSettings/ChatEditedIndicatorPreferences.swift", source)
    shutil.copy(root / "packages/ChatUI/Tests/ChatUITests/ChatEditedIndicatorPreferencesTests.swift", tests)
    (workspace / "Package.swift").write_text(f"""// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GergramChatEditedIndicator",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: {json.dumps(str(signal_kit))})],
    targets: [
        .target(name: "InAppSettings", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources"),
        .testTarget(name: "ChatEditedIndicatorTests", dependencies: ["InAppSettings"], path: "Tests"),
    ]
)
""")
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(workspace / "ClangCache"),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / "SwiftPMCache"))
    command = ["swift", "test", "--package-path", str(workspace), "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    raise SystemExit(subprocess.run(command, env=environment).returncode)
