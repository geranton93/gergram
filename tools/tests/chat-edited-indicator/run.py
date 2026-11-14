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
parser.add_argument("--sanitize", choices=["address"])
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
    for name in ["ChatEditedIndicatorPreferences.swift", "ChatIndicatorCustomText.swift", "ArchiveDeletedMarkPreferences.swift"]:
        shutil.copy(root / "packages/InAppSettings/Sources/InAppSettings" / name, source)
    shutil.copy(root / "packages/ChatUI/Tests/ChatUITests/ChatEditedIndicatorPreferencesTests.swift", tests)
    archive = (root / "packages/SettingsUI/Sources/SettingsUI/LocalMessageArchiveController.swift").read_text()
    fixture = (root / "tools/tests/archive-deleted-mark/ArchiveDeletedMarkTests.swift").read_text()
    entry = archive[archive.index("private struct ArchiveEntry:"):archive.index("private struct ArchivePageState:")]
    editor = archive[archive.index("private func activeArchiveMarkNavigation("):archive.index("private func archiveDate(")]
    open_editor = archive[archive.index("    func editDeletedMark()"):archive.index("    private func load(before cursor:")]
    fixture = fixture.replace("__ARCHIVE_ENTRY__", entry).replace("__ARCHIVE_EDITOR__", editor)
    (tests / "ArchiveDeletedMarkTests.swift").write_text(fixture.replace("__OPEN_EDITOR__", open_editor))
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
    if args.sanitize:
        command.extend(["--sanitize", args.sanitize])
    raise SystemExit(subprocess.run(command, env=environment).returncode)
