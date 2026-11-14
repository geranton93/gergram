import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).resolve().parent
PINNED = {
    "Postbox.swift": "72585b34e1b31c181fd178f32a6d62fcb4ecb26e",
    "ValueBox.swift": "f4f5bdafa635f0ec2d98e190e5b9d8d4a26ea96b",
    "ValueBoxKey.swift": "021adfaa69b980a4e83a2da644dcb86ba01f54ff",
    "Peer.swift": "60ef42caceac64b60a9ff105e1974b7c0596b22a",
    "Message.swift": "a3a0bd715d60809d66295a05c7069b798195daee",
    "Coding.swift": "1279ab531cebb026aaddd21849bfeb68a22e0ecf",
    "SqliteValueBox.swift": "79ff0508e0365352fec9d434e84fa2c4cc9f6bca",
    "Database.swift": "32a31a5c96287b7958514c0b6a405c5980d09429",
}


def pinned_source(directory, name):
    path = directory / name
    actual = subprocess.check_output(["git", "hash-object", str(path)], text=True).strip()
    if actual != PINNED[name]:
        raise ValueError(f"{name} differs from the pinned Postbox revision")
    return path.read_text()


def run(pinned, signal_build, directory):
    sources = directory / "submodules" / "Postbox" / "Sources"
    sources.mkdir(parents=True)
    (sources / "Postbox.swift").write_text(pinned_source(pinned, "Postbox.swift"))
    subprocess.run(["git", "init", "-q", str(directory)], check=True)
    archive = sources / "LocalMessageArchive.swift"
    patch = ROOT / "scripts" / "telegram-ios-macos.patch"
    subprocess.run([
        "git", "-C", str(directory), "apply",
        "--include=submodules/Postbox/Sources/LocalMessageArchive.swift",
        "--include=submodules/Postbox/Sources/Postbox.swift", str(patch),
    ], check=True)
    subprocess.run(["xcrun", "swiftc", "-frontend", "-parse", str(sources / "Postbox.swift")], check=True)

    fixture = directory / "fixture"
    fixture.mkdir()
    maintenance_path = Path("submodules/TelegramCore/Sources/Account/LocalArchiveMaintenance.swift")
    subprocess.run([
        "git", "-C", str(directory), "apply", f"--include={maintenance_path}",
        str(ROOT / "scripts" / "telegram-ios-local-archive-maintenance.patch"),
    ], check=True)
    (fixture / maintenance_path.name).write_text((directory / maintenance_path).read_text().replace("import Postbox\n", ""))
    for name in ("ArchiveTests.swift", "Support.swift"):
        shutil.copyfile(FIXTURE / name, fixture / name)
    for name in ("ValueBox.swift", "ValueBoxKey.swift", "SqliteValueBox.swift", "Database.swift"):
        text = pinned_source(pinned, name).replace("import sqlcipher", "import SQLite3")
        (fixture / name).write_text(text)

    peer = pinned_source(pinned, "Peer.swift").split("public protocol Peer: AnyObject, PostboxCoding {", 1)[0]
    message = pinned_source(pinned, "Message.swift").split("public struct MessageIndex: Codable, Comparable, Hashable {", 1)[0]
    coding = pinned_source(pinned, "Coding.swift")
    buffers = coding[coding.index("private let emptyMemory ="):coding.index("enum ValueType: Int8 {")]
    (fixture / "PinnedIdentifiers.swift").write_text(peer + message + buffers)

    executable = directory / "archive-tests"
    command = ["xcrun", "swiftc", "-O", "-module-cache-path", str(directory / "cache")]
    if os.environ.get("GERGRAM_TEST_ASAN") == "1":
        command.append("-sanitize=address")
    subprocess.run([
        *command,
        "-I", str(signal_build), str(signal_build / "libSwiftSignalKit.a"),
        *map(str, sorted(fixture.glob("*.swift"))), str(archive), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("pinned", type=Path, help="Directory with original pinned Postbox sources")
    parser.add_argument("signal_build", type=Path, help="Directory containing the pinned SwiftSignalKit module and static library")
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="gergram-local-archive-") as scratch:
        run(arguments.pinned.resolve(), arguments.signal_build.resolve(), Path(scratch))
