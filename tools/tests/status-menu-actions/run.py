import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def section(source, start, end):
    beginning = source.index(start)
    return source[beginning:source.index(end, beginning)]


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description="Verify active-account status menu actions with native AppKit.")
parser.add_argument("--signal-kit", type=Path, default=root / "submodules/telegram-ios/submodules/SSignalKit")
parser.add_argument("--sanitize", choices=["address"])
args = parser.parse_args()
signal_kit = args.signal_kit.resolve()
if not (signal_kit / "Package.swift").is_file():
    parser.error("Initialize the Telegram-iOS submodule or provide its pinned SSignalKit through --signal-kit.")

shared = (root / "Telegram-Mac/account/SharedAccountContext.swift").read_text()
delegate = (root / "Telegram-Mac/app/AppDelegate.swift").read_text()
fixture = Path(__file__).with_name("StatusMenuFixture.swift").read_text()
parts = {
    "__OBSERVE__": section(shared, "        statusMenuVisibilityDisposable.set(", "        #endif").replace(
        "StreamerModeMenuBarPreferences.shared.actionsSignal", "preferences.actionsSignal"),
    "__GATE__": section(shared, "    func canOpenStatusMenuAction(", "    func updateStreamerModeMenuState"),
    "__MENU__": section(shared, "    private func updateStatusBarMenuItem()", "    private func updateStatusBar(_ show"),
    "__ACTIONS__": section(delegate, "    private struct AccountStatusMenuSelection", "    @objc private func toggleStreamerMode").replace(
        "        NSApp.activate(ignoringOtherApps: true)\n", ""),
}
for marker, source in parts.items():
    fixture = fixture.replace(marker, source)

# The fixture uses a native NSMenu and selector delivery. Account, screen activation and navigation are local doubles.
with tempfile.TemporaryDirectory(prefix="gergram-status-menu-") as directory:
    workspace = Path(directory)
    sources = workspace / "Sources"
    sources.mkdir()
    (sources / "main.swift").write_text(fixture)
    shutil.copy(root / "packages/InAppSettings/Sources/InAppSettings/StreamerModeMenuBarPreferences.swift", sources)
    (workspace / "Package.swift").write_text(f'''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StatusMenuCheck", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: {json.dumps(str(signal_kit))})],
    targets: [.executableTarget(name: "StatusMenuCheck", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources")])
''')
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(workspace / "ClangCache"),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / "SwiftPMCache"))
    command = ["xcrun", "swift", "run", "--package-path", directory, "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    if args.sanitize:
        command.extend(["--sanitize", args.sanitize])
    raise SystemExit(subprocess.run(command, env=environment).returncode)
