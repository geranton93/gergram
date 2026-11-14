import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
chat_ui = root / "packages/ChatUI"
ios = root / "submodules/telegram-ios"
pin = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
network = Path("submodules/TelegramCore/Sources/Network")
blobs = {
    network / "FetchV2.swift": "c916f267d9232cea1f3362aa5c365174531b46b4",
    network / "Network.swift": "d0a36f610d35fbb06435168a83d04ac4ccb9455b",
}
patch = root / "scripts/telegram-ios-speed-notice-download.patch"

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ios)
parser.add_argument("--signal-package", type=Path, default=ios / "submodules/SSignalKit")
parser.add_argument("--sanitize", choices=["address"])
args = parser.parse_args()


def pinned_bytes(path):
    source = args.source.resolve()
    if (source / ".git").exists():
        raw = subprocess.check_output(["git", "-C", str(source), "show", f"{pin}:{path}"])
    else:
        raw = (source / path).read_bytes()
    digest = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    if digest != blobs[path]:
        raise ValueError(f"{path} differs from its pinned Telegram-iOS blob")
    return raw


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


with tempfile.TemporaryDirectory(prefix="network-speed-notice-") as scratch:
    directory = Path(scratch)
    patched = directory / "telegram-ios"
    for path in blobs:
        target = patched / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pinned_bytes(path))
    subprocess.run(["git", "init", "-q", str(patched)], check=True)
    apply = ["git", "-C", str(patched), "apply"]
    for flags in (["--check"], [], ["--reverse", "--check"]):
        subprocess.run([*apply, *flags, str(patch)], check=True)
    fetch = (patched / network / "FetchV2.swift").read_text()
    core = (patched / network / "Network.swift").read_text()
    subprocess.run([*apply, "--reverse", str(patch)], check=True)
    for path in blobs:
        assert (patched / path).read_bytes() == pinned_bytes(path)

    source = chat_ui / "Sources/ChatUI"
    policy = (source / "ChatNetworkSpeedNotice.swift").read_text()
    shared_tests = (chat_ui / "Tests/ChatUITests/ChatNetworkSpeedNoticeTests.swift").read_text()
    controller = (source / "ChatController.swift").read_text()
    fixture = Path(__file__).with_name("NetworkSpeedNoticeTests.swift").read_text()
    for marker, code in {
        "__CORE_PIPE__": section(core, "    public var networkSpeedLimitedEvents:", "    public func dropConnectionStatus"),
        "__CORE_STATE__": section(core, "private final class NetworkSpeedLimitedEventState", "public final class Network:"),
        "__CORE_PUBLICATION__": section(core, "    func updateNetworkSpeedLimitedEventNotifyInterval(", "\n}\n\nfunc networkRequestErrorPolicy"),
        "__FLOOD_CALLBACK__": section(fetch, "                            onFloodWaitError: { [weak self, weak state, weak part]", ", expectedResponseSize: Int32(requestedLength)")
            .strip().removeprefix("onFloodWaitError: "),
        "__FLOOD_EVENT__": section(fetch, "        private func processFloodWaitError(", "\n    }\n"),
        "__CONTROLLER_NOTICE__": section(controller, "    private var isSpeedNoticeAccountActive:", "    private func presentNetworkSpeedNotice(")
            .replace("private func", "func"),
    }.items():
        fixture = fixture.replace(marker, code)
    tests = directory / "Tests"
    tests.mkdir()
    for name, text in (
        ("NetworkSpeedNoticeTests.swift", fixture),
        ("ChatNetworkSpeedNotice.swift", policy),
        ("ChatNetworkSpeedNoticeTests.swift", shared_tests),
    ):
        for statement in ("import Postbox\n", "import TelegramCore\n", "@testable import ChatUI\n"):
            text = text.replace(statement, "")
        (tests / name).write_text(text)

    signal = json.dumps(str(args.signal_package.resolve()))
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "NetworkSpeedNotice", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + signal + ''')],
    targets: [.testTarget(name: "NetworkSpeedNoticeTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ["swift", "test", "--package-path", str(directory), "--manifest-cache", "none", "--disable-sandbox", "--jobs", "4"]
    if args.sanitize:
        command.extend(["--sanitize", args.sanitize])
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
    environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
    subprocess.run(command, check=True, env=environment)
