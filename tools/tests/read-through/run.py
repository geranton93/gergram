import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).resolve().parent
PIN = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
POSTBOX = Path("submodules/Postbox/Sources")
MESSAGES = Path("submodules/TelegramCore/Sources/TelegramEngine/Messages")
PATCH = ROOT / "scripts/telegram-ios-read-through.patch"
CHAT_UI = ROOT / "packages/ChatUI"
READ_STATE = POSTBOX / "MessageHistoryReadStateTable.swift"
READ_TRANSACTION = MESSAGES / "ApplyMaxReadIndexInteractively.swift"
PINNED = {
    POSTBOX / "Postbox.swift": "72585b34e1b31c181fd178f32a6d62fcb4ecb26e",
    POSTBOX / "MessageHistoryTable.swift": "17f3fee96e0644a074432488b1d78248ddac00b3",
    POSTBOX / "PeerReadState.swift": "25385872ddcdd43a5a9a6f4f288015540c1b1734",
    READ_STATE: "c6926cd1ed03050475e9efb144abad1df797b618",
    READ_TRANSACTION: "0e26cab4c2631a986deb1f9bbdbd6b056a7087b4",
    MESSAGES / "TelegramEngineMessages.swift": "21020ed0aa5738453d683da1bd4e01b32ec95fa4",
}


def pinned_bytes(source, path):
    if (source / ".git").exists():
        raw = subprocess.check_output(["git", "-C", str(source), "show", f"{PIN}:{path}"])
    else:
        raw = (source / path).read_bytes()
    digest = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    if digest != PINNED[path]:
        raise ValueError(f"{path} differs from the pinned Telegram-iOS blob")
    return raw


def prepare_source(source, destination):
    for path in PINNED:
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pinned_bytes(source, path))
    subprocess.run(["git", "init", "-q", str(destination)], check=True)
    apply = ["git", "-C", str(destination), "apply"]
    subprocess.run([*apply, "--check", str(PATCH)], check=True)
    subprocess.run([*apply, str(PATCH)], check=True)
    subprocess.run([*apply, "--reverse", "--check", str(PATCH)], check=True)


def extract_function(source, name, indent=""):
    start = source.index(f"\n{indent}func {name}(") + 1
    end = source.index(f"\n{indent}}}", start) + len(indent) + 2
    return source[start:end]


def prepare_tests(patched, directory):
    tests = directory / "Tests"
    tests.mkdir()
    table = (patched / READ_STATE).read_text()
    engine = (patched / READ_TRANSACTION).read_text()
    methods = "\n\n".join(extract_function(table, name, "    ") for name in (
        "applyIncomingMaxReadId", "applyInteractiveMaxReadIndex",
    ))
    template = (FIXTURE / "Support.swift.in").read_text()
    support = template.replace("__READ_STATE_METHODS__", methods).replace(
        "__READ_THROUGH_TRANSACTION__", extract_function(engine, "_internal_applyReadThroughMessageInteractively")
    )
    (tests / "Support.swift").write_text(support)
    for source in (
        CHAT_UI / "Sources/ChatUI/ChatReadUntilPolicy.swift",
        CHAT_UI / "Tests/ChatUITests/ChatReadUntilTests.swift",
        patched / POSTBOX / "PeerReadState.swift",
        FIXTURE / "ExactReadThroughTests.swift",
    ):
        text = re.sub(r"^(?:@testable )?import (?!XCTest\b)\w+\n", "", source.read_text(), flags=re.MULTILINE)
        (tests / source.name).write_text(text)
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ReadThroughFixture", targets: [.testTarget(name: "ReadThroughTests", path: "Tests")])
''')


def main():
    parser = argparse.ArgumentParser(description="Run the pinned native read-through fixtures.")
    parser.add_argument("--source", type=Path, default=ROOT / "submodules/telegram-ios",
                        help="Pinned Telegram-iOS checkout or an unmodified source tree")
    parser.add_argument("--sanitize", choices=["address"])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="gergram-read-through-") as scratch:
        directory = Path(scratch)
        patched = directory / "patched"
        try:
            prepare_source(args.source.resolve(), patched)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            parser.exit(1, f"Unable to prepare pinned read-through sources. {error}\n")
        prepare_tests(patched, directory)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(directory / "swift-cache")
        command = ["xcrun", "swift", "test", "--package-path", str(directory), "--manifest-cache", "none", "--disable-sandbox"]
        if args.sanitize:
            command.extend(["--sanitize", args.sanitize])
        subprocess.run(command, check=True, env=environment)


if __name__ == "__main__":
    main()
