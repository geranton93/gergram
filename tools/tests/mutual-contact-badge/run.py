import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description="Run the Contacts badge tests against the pinned Telegram user flags.")
parser.add_argument("--telegram-user-source", type=Path)
args = parser.parse_args()
if args.telegram_user_source is None:
    core = root / "submodules/telegram-ios/submodules/TelegramCore"
    matches = list(core.rglob("SyncCore_TelegramUser.swift"))
    if len(matches) != 1:
        parser.error("Initialize the telegram-ios submodule or supply --telegram-user-source.")
    args.telegram_user_source = matches[0]

telegram_user = args.telegram_user_source.read_text()
flags_start = telegram_user.index("public struct UserInfoFlags: OptionSet")
flags_end = telegram_user.index("public struct BotUserInfoFlags: OptionSet", flags_start)
sources = root / "packages/ChatListUI/Sources/ChatListUI"
test_sources = root / "packages/ChatListUI/Tests/ChatListUITests"
policy = sources / "ContactMutualBadge.swift"
suite = test_sources / "ContactMutualBadgeTests.swift"

with tempfile.TemporaryDirectory(prefix="gergram-mutual-contact-badge-") as directory:
    workspace = Path(directory)
    tests = workspace / "Tests"
    tests.mkdir()
    (workspace / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GergramContactMutualBadge",
    platforms: [.macOS(.v10_13)],
    targets: [.testTarget(name: "ContactMutualBadgeTests", path: "Tests")]
)
""")
    (tests / "UserInfoFlags.swift").write_text(telegram_user[flags_start:flags_end])
    (tests / policy.name).write_text(policy.read_text().removeprefix("import TelegramCore\n"))
    (tests / suite.name).write_text(suite.read_text().removeprefix("import TelegramCore\n").replace("@testable import ChatListUI\n", ""))
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(workspace / "ClangCache"),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / "SwiftPMCache"))
    command = ["swift", "test", "--package-path", str(workspace), "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    raise SystemExit(subprocess.run(command, env=environment).returncode)
