import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description="Test the search preview projection with SwiftSignalKit.")
parser.add_argument("--signal-kit", type=Path, default=root / "submodules/telegram-ios/submodules/SSignalKit")
parser.add_argument("--sanitize", choices=["address"])
args = parser.parse_args()
signal_kit = args.signal_kit.resolve()
if not (signal_kit / "Package.swift").is_file():
    parser.error("Missing SSignalKit package. Initialize telegram-ios or supply --signal-kit.")

sources = root / "packages/ChatListUI/Sources/ChatListUI"
controller = (sources / "SearchController.swift").read_text()
entry = controller[controller.index("private struct SearchSecretChatWrapper"):controller.index("private func peerContextMenuItems(")]
projection = controller[controller.index("let transition = combineLatest(queue: prepareQueue, searchItems,"):]
projection = projection[:projection.index("\n        |> map { entries, loading,")]
projection = projection.replace("context.globalPeerHandler.get() |> distinctUntilChanged", "locationSignal")
projection = projection.replace("FastSettings.filterZalgoTextSignal", "filter.get()")
fixture = Path(__file__).with_name("SearchZalgoTests.swift").read_text()
fixture = fixture.replace("__SEARCH_ENTRY__", entry).replace("__SEARCH_PROJECTION__", projection)

with tempfile.TemporaryDirectory(prefix="gergram-search-zalgo-") as directory:
    workspace = Path(directory)
    tests = workspace / "Tests"
    tests.mkdir()
    (tests / "SearchZalgoTests.swift").write_text(fixture)
    preference = (sources / "ChatListZalgoPreview.swift").read_text()
    preference = preference[preference.index("    static func isEligible"):]
    (tests / "ChatListZalgoPreview.swift").write_text("import Foundation\n\nenum ChatListZalgoPreview {\n" + preference)
    shutil.copy(root / "packages/MessageTextUtils/Sources/MessageTextUtils/ChatZalgoTextFilter.swift", tests)
    (workspace / "Package.swift").write_text(f"""// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GergramSearchZalgo",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: {json.dumps(str(signal_kit))})],
    targets: [.testTarget(name: "SearchZalgoTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
""")
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(workspace / "ClangCache"),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / "SwiftPMCache"))
    command = ["swift", "test", "--package-path", str(workspace), "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    if args.sanitize:
        command.extend(["--sanitize", args.sanitize])
    raise SystemExit(subprocess.run(command, env=environment).returncode)
