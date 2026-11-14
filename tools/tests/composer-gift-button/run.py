import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
chat = root / "packages/ChatUI/Sources/ChatUI"
settings = root / "packages/InAppSettings/Sources/InAppSettings"
fixture = Path(__file__).with_name("ComposerGiftButtonTests.swift").read_text()
actions = (chat / "ChatInputActionsView.swift").read_text()
parts = {
    "__BIND__": ("        giftButtonPreferenceDisposable.set(", "\n    }"),
    "__UPDATE__": ("    @discardableResult\n    private func updateGiftButton", "    public override func updateLocalizationAndTheme"),
    "__BUTTONS__": ("    private static let extraButtonSize", "    public func secretTimerItems"),
}
for marker, (start_text, end_text) in parts.items():
    start = actions.index(start_text)
    end = actions.index(end_text, start)
    fixture = fixture.replace(marker, actions[start:end])
fixture += "\n" + (settings / "ComposerGiftButtonPreferences.swift").read_text()
policy = (chat / "ChatComposerGiftButtonVisibility.swift").read_text()
fixture += "\n" + policy[policy.index("extension ChatPresentationInterfaceState"):]
with tempfile.TemporaryDirectory(prefix="gergram-composer-gift-button-") as path:
    directory = Path(path)
    (directory / "Tests").mkdir()
    (directory / "Tests/ComposerGiftButtonTests.swift").write_text(fixture)
    signal = json.dumps(os.environ.get("GERGRAM_SIGNAL_PACKAGE", str(root / "submodules/telegram-ios/submodules/SSignalKit")))
    (directory / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "ComposerGiftButton",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: """ + signal + """)],
    targets: [.testTarget(name: "ComposerGiftButtonTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
""")
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(directory / "module-cache"))
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", str(directory / "module-cache"))
    command = ["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", *sys.argv[1:]]
    raise SystemExit(subprocess.run(command, env=env).returncode)
