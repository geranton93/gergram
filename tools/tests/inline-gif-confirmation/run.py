import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
chat = root / "packages/ChatUI/Sources/ChatUI"
controller = (chat / "ChatController.swift").read_text()
start = controller.index("        chatInteraction.sendInlineResult = {")
end = controller.index("        chatInteraction.beginEditingMessage", start)
conformance = (chat / "ChatInteractionFeatureConformances.swift").read_text()
policy_start = conformance.index("    public func shouldDeferInlineResultSendFlight")
policy_end = conformance.index("    public func sendFile", policy_start)
fixture = Path(__file__).with_name("InlineGifTests.swift").read_text()
fixture = fixture.replace("__SEND__", controller[start:end]).replace("__POLICY__", conformance[policy_start:policy_end])
start = controller.index("    private func confirmInlineGifSend")
end = controller.index("    private func confirmRecordingSendIfEnabled", start)
fixture = fixture.replace("__CONFIRM__", controller[start:end])
fixture += "\n" + (chat / "ChatInlineGifSend.swift").read_text().replace("import TelegramCore\n", "")
fixture += "\n" + (chat / "ChatMediaSendConfirmation.swift").read_text()
fixture += "\n" + (chat / "ChatDeferredSendAction.swift").read_text().split("\nfunc chatHasSameDeferredSendState", 1)[0]

with tempfile.TemporaryDirectory(prefix="gergram-inline-gif-") as directory:
    directory = Path(directory)
    (directory / "Tests").mkdir()
    (directory / "Tests/InlineGifTests.swift").write_text(fixture)
    signal = json.dumps(os.environ.get("GERGRAM_SIGNAL_PACKAGE", str(root / "submodules/telegram-ios/submodules/SSignalKit")))
    (directory / "Package.swift").write_text("""// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "InlineGifConfirmation",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: """ + signal + """)],
    targets: [.testTarget(name: "InlineGifConfirmationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
""")
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(directory / "module-cache"))
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", str(directory / "module-cache"))
    command = ["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "4", *sys.argv[1:]]
    raise SystemExit(subprocess.run(command, env=env).returncode)
