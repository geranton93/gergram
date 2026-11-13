import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
policy = root / "packages/ChatUI/Sources/ChatUI/ChatChannelAuthorBadge.swift"
suite = root / "packages/ChatUI/Tests/ChatUITests/ChatChannelAuthorBadgeTests.swift"

with tempfile.TemporaryDirectory(prefix="gergram-channel-author-badge-") as directory:
    workspace = Path(directory)
    tests = workspace / "Tests"
    tests.mkdir()
    (workspace / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GergramChannelAuthorBadge",
    platforms: [.macOS(.v10_13)],
    targets: [.testTarget(name: "ChannelAuthorBadgeTests", path: "Tests")]
)
""")
    (tests / "TelegramChannelInfo.swift").write_text("""enum TelegramChannelInfo {
    struct Info {
        let flags: [Int]
    }

    case group(Info)
    case broadcast(Info)
}
""")
    (tests / policy.name).write_text(policy.read_text().replace("import TelegramCore\n", ""))
    (tests / suite.name).write_text(suite.read_text().replace("import TelegramCore\n", "").replace("@testable import ChatUI\n", ""))
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(workspace / "ClangCache"),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / "SwiftPMCache"))
    command = ["swift", "test", "--package-path", str(workspace), "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    raise SystemExit(subprocess.run(command, env=environment).returncode)
