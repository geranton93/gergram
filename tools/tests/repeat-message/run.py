import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
sources = root / "packages/ChatUI/Sources/ChatUI"
fixture = Path(__file__).with_name("RepeatMessageTests.swift").read_text()
for name in ("ChatRepeatMessageAction", "ChatMediaSendConfirmation", "ChatDeferredSendAction"):
    production = (sources / (name + ".swift")).read_text()
    if name == "ChatDeferredSendAction":
        production = production.split("\nfunc chatHasSameDeferredSendState", 1)[0]
    fixture += "\n" + "\n".join(line for line in production.splitlines() if not line.startswith("import "))
fixture += "\n" + (root / "packages/InAppSettings/Sources/InAppSettings/MessageContextMenuPreferences.swift").read_text()
with tempfile.TemporaryDirectory(prefix="gergram-repeat-message-") as path:
    directory = Path(path)
    (directory / "Tests").mkdir()
    (directory / "Tests/RepeatMessageTests.swift").write_text(fixture)
    signal = json.dumps(os.environ.get("GERGRAM_SIGNAL_PACKAGE", str(root / "submodules/telegram-ios/submodules/SSignalKit")))
    (directory / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "RepeatMessage",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: """ + signal + """)],
    targets: [.testTarget(name: "RepeatMessageTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
""")
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(directory / "module-cache"))
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", str(directory / "module-cache"))
    command = ["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", *sys.argv[1:]]
    raise SystemExit(subprocess.run(command, env=env).returncode)
