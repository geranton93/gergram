import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
chat = root / "packages/ChatUI/Sources/ChatUI"
settings = root / "packages/InAppSettings/Sources/InAppSettings"
fixture = Path(__file__).with_name("ComposerBotCommandsTests.swift").read_text()
input_view = (chat / "ChatInputView.swift").read_text()
start = input_view.index("        composerBotCommandsDisposable.set(")
end = input_view.index("\n    }", start)
fixture = fixture.replace("__BIND__", input_view[start:end])
start = input_view.index("    private func updateComposerBotCommandsVisibility(")
end = input_view.index("    private func scheduleInlineRichDraftStore(", start)
fixture = fixture.replace("__UPDATE__", input_view[start:end])
start = input_view.index("    public func updateAttachments(")
end = input_view.index("    public func updateLayout(size:", start)
fixture = fixture.replace("__ATTACHMENTS__", input_view[start:end])
container_start = input_view.index("    public func textViewSize(")
container_end = input_view.index("    private func sendSlot(", container_start)
fixture = fixture.replace("__WIDTH__", input_view[container_start:container_end])
fixture += "\n" + (settings / "ComposerBotCommandsPreferences.swift").read_text()
fixture += "\n" + (chat / "ChatComposerBotMenuVisibility.swift").read_text()
fixture += "\n" + (chat / "TelegramCommandAutocomplete.swift").read_text()
query = (chat / "ChatInterfaceInputContext.swift").read_text()
fixture += "\n" + query[query.index("public struct PossibleContextQueryTypes:"):]

with tempfile.TemporaryDirectory(prefix="gergram-composer-bot-commands-") as path:
    directory = Path(path)
    (directory / "Tests").mkdir()
    (directory / "Tests/ComposerBotCommandsTests.swift").write_text(fixture)
    signal = json.dumps(os.environ.get("GERGRAM_SIGNAL_PACKAGE", str(root / "submodules/telegram-ios/submodules/SSignalKit")))
    (directory / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "ComposerBotCommands",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: """ + signal + """)],
    targets: [.testTarget(name: "ComposerBotCommandsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
""")
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(directory / "module-cache"))
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", str(directory / "module-cache"))
    command = ["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", *sys.argv[1:]]
    raise SystemExit(subprocess.run(command, env=env).returncode)
