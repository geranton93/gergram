import argparse
import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).resolve().parent
POSTBOX = Path("submodules/Postbox/Sources")
CORE = Path("submodules/TelegramCore/Sources")
SYNC = CORE / "State/Sync"
SYNCCORE = CORE / "SyncCore"
CAPTURE_PATCH = ROOT / "scripts/telegram-ios-local-archive-capture.patch"
ARCHIVE_PATCH = ROOT / "scripts/telegram-ios-macos.patch"
MAINTENANCE_PATCH = ROOT / "scripts/telegram-ios-local-archive-maintenance.patch"
NOTIFICATION_PATCH = ROOT / "scripts/telegram-ios-notification-timing.patch"
READ_THROUGH_PATCH = ROOT / "scripts/telegram-ios-read-through.patch"
READ_FORUM_THROUGH_PATCH = ROOT / "scripts/telegram-ios-read-forum-through.patch"
REPEAT_PHOTO_REFERENCE_PATCH = ROOT / "scripts/telegram-ios-repeat-photo-reference.patch"
SPEED_NOTICE_DOWNLOAD_PATCH = ROOT / "scripts/telegram-ios-speed-notice-download.patch"
SWIFTPM_PATHS_PATCH = ROOT / "scripts/telegram-ios-swiftpm-paths.patch"
PINNED = {
    POSTBOX / "Postbox.swift": "72585b34e1b31c181fd178f32a6d62fcb4ecb26e",
    POSTBOX / "ValueBoxKey.swift": "021adfaa69b980a4e83a2da644dcb86ba01f54ff",
    POSTBOX / "Peer.swift": "60ef42caceac64b60a9ff105e1974b7c0596b22a",
    POSTBOX / "Message.swift": "a3a0bd715d60809d66295a05c7069b798195daee",
    POSTBOX / "Coding.swift": "1279ab531cebb026aaddd21849bfeb68a22e0ecf",
    POSTBOX / "PreferencesEntry.swift": "09ad00e9055085658908dae7517b2ac00f739758",
    CORE / "Account/Account.swift": "510cb791803236ef8b530fee856b569bbc22d814",
    CORE / "Account/AccountIntermediateState.swift": "b3052428da309fb932f8f63ca594f400d0c926fe",
    CORE / "Account/AccountManager.swift": "c3c37c555de662b93fa00d8d5cfec50c5ed5f661",
    SYNC / "StateReplay.swift": "4ca07602e961da1d2e80656e3774ddf2678e1d17",
    SYNC / "StateReplay+Messages.swift": "cf1ab15d9cfae956abcb53bf5060db525b32448d",
    SYNC / "SyncResolve.swift": "63af85bc0a2512812655bd460c98986ce90ac3b9",
    SYNC / "UpdateInterpreter+Channels.swift": "bc1b7b54a39f4155dc678714e65cf8131c6ca2e7",
    SYNC / "UpdateInterpreter+Messages.swift": "24f8b816944de5b26bc8917d36da55962f2c3613",
    CORE / "TelegramEngine/Wallet/WalletTonConnect.swift": "f07a73928bea9333e2a0e08607776f29ad5c03b1",
    SYNCCORE / "SyncCore_TextEntitiesMessageAttribute.swift": "db354b607912ccc651030003d8dc5c0f692b1681",
    SYNCCORE / "SyncCore_TelegramMediaFile.swift": "c12943c0aad861cc36b47e0af30f456a0058501b",
    SYNCCORE / "SyncCore_EditedMessageAttribute.swift": "e6b7625b779fc0574909acb74689adac1c1926b5",
    SYNCCORE / "SyncCore_ChannelMessageStateVersionAttribute.swift": "cb47d634a185da918958ce5280c40c6052539138",
}
CHANGED = (
    CORE / "Account/AccountIntermediateState.swift",
    SYNC / "StateReplay.swift",
    SYNC / "StateReplay+Messages.swift",
    SYNC / "SyncResolve.swift",
    SYNC / "UpdateInterpreter+Channels.swift",
    SYNC / "UpdateInterpreter+Messages.swift",
    CORE / "TelegramEngine/Wallet/WalletTonConnect.swift",
)
MAINTENANCE_CHANGED = (
    CORE / "Account/Account.swift",
    CORE / "Account/AccountManager.swift",
)


def read_pinned(source, path):
    raw = (source / path).read_bytes()
    digest = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    if digest != PINNED[path]:
        raise ValueError(f"{path} differs from the pinned Telegram-iOS revision")
    return raw.decode()


def apply_patches(source, work):
    subprocess.run(["git", "init", "-q", str(work)], check=True)
    for relative in (*CHANGED, *MAINTENANCE_CHANGED, POSTBOX / "Postbox.swift"):
        path = work / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(read_pinned(source, relative))
    git = ["git", "-C", str(work), "apply"]
    subprocess.run([
        *git, f"--include={POSTBOX / 'Postbox.swift'}",
        f"--include={POSTBOX / 'LocalMessageArchive.swift'}", str(ARCHIVE_PATCH),
    ], check=True)
    subprocess.run([*git, "--check", str(CAPTURE_PATCH)], check=True)
    subprocess.run([*git, str(CAPTURE_PATCH)], check=True)
    subprocess.run([*git, "--reverse", "--check", str(CAPTURE_PATCH)], check=True)
    subprocess.run([*git, "--check", str(MAINTENANCE_PATCH)], check=True)
    subprocess.run([*git, str(MAINTENANCE_PATCH)], check=True)
    subprocess.run([*git, "--reverse", "--check", str(MAINTENANCE_PATCH)], check=True)
    subprocess.run([
        "xcrun", "swiftc", "-frontend", "-parse",
        *(str(work / path) for path in (*CHANGED, *MAINTENANCE_CHANGED)),
        str(work / SYNC / "LocalArchiveCapture.swift"),
        str(work / POSTBOX / "LocalArchiveCaptureSettings.swift"),
        str(work / CORE / "Account/LocalArchiveMaintenance.swift"),
    ], check=True)


def run_preparation_fixture(directory):
    project = directory / "prepare-project"
    scripts = project / "scripts"
    scripts.mkdir(parents=True)
    shutil.copyfile(ROOT / "scripts/prepare-telegram-ios.sh", scripts / "prepare-telegram-ios.sh")
    ios = project / "submodules/telegram-ios"
    ios.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(ios)], check=True)
    voip = ios / "submodules/TelegramVoip/Package.swift"
    voip.parent.mkdir(parents=True)
    voip.touch()
    paths = (
        Path("base.swift"), POSTBOX / "Postbox.swift", SYNC / "StateReplay.swift", CORE / "Account/Account.swift",
        CORE / "State/AccountStateManager.swift", POSTBOX / "MessageHistoryReadStateTable.swift",
        POSTBOX / "MessageHistoryTable.swift", CORE / "PendingMessages/PendingMessageUploadedContent.swift",
        CORE / "Network/FetchV2.swift", CORE / "Network/Network.swift",
        Path("submodules/ManagedFile/Package.swift"),
    )
    for path in paths:
        target = ios / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("before\n")
    subprocess.run(["git", "-C", str(ios), "add", "."], check=True)
    diff = ["git", "-C", str(ios), "diff"]
    for path in paths:
        (ios / path).write_text("after\n")
    archive = POSTBOX / "LocalMessageArchive.swift"
    capture = SYNC / "LocalArchiveCapture.swift"
    maintenance = CORE / "Account/LocalArchiveMaintenance.swift"
    notification = CORE / "State/NotificationDeliveryTiming.swift"
    read_through = CORE / "TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift"
    for path in (archive, capture, maintenance, notification, read_through):
        (ios / path).parent.mkdir(parents=True, exist_ok=True)
        (ios / path).write_text("new\n")
    subprocess.run(["git", "-C", str(ios), "add", "-N", str(archive), str(capture), str(maintenance), str(notification), str(read_through)], check=True)
    (scripts / ARCHIVE_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[0]), str(paths[1]), str(archive)]))
    (scripts / CAPTURE_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[2]), str(capture)]))
    (scripts / MAINTENANCE_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[3]), str(maintenance)]))
    (scripts / NOTIFICATION_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[4]), str(notification)]))
    (scripts / READ_THROUGH_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[5]), str(read_through)]))
    (scripts / READ_FORUM_THROUGH_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[6])]))
    (scripts / REPEAT_PHOTO_REFERENCE_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[7])]))
    (scripts / SPEED_NOTICE_DOWNLOAD_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[8]), str(paths[9])]))
    (scripts / SWIFTPM_PATHS_PATCH.name).write_bytes(subprocess.check_output([*diff, "--", str(paths[10])]))
    prepare = ["sh", str(scripts / "prepare-telegram-ios.sh")]
    for _ in range(2):
        subprocess.run([*prepare, "--reverse"], check=True)
    assert not any((ios / path).exists() for path in (archive, capture, maintenance, notification, read_through))
    assert all((ios / path).read_text() == "before\n" for path in paths)
    subprocess.run(["git", "-C", str(ios), "apply", str(scripts / ARCHIVE_PATCH.name)], check=True)
    subprocess.run(["git", "-C", str(ios), "apply", str(scripts / CAPTURE_PATCH.name)], check=True)
    for _ in range(2):
        subprocess.run(prepare, check=True)
    assert all((ios / path).exists() for path in (archive, capture, maintenance, notification, read_through))
    assert all((ios / path).read_text() == "after\n" for path in paths)
    subprocess.run([*prepare, "--reverse"], check=True)
    (ios / paths[4]).write_text("conflict\n")
    failure = subprocess.run(prepare, capture_output=True)
    assert failure.returncode != 0 and not (ios / archive).exists()
    assert all((ios / path).read_text() == "before\n" for path in paths[:4])
    print("PASS reversible preparation, existing patch upgrade and preflight")


def run_capture_fixture(source, work, directory):
    fixture = directory / "fixture"
    fixture.mkdir()
    peer = read_pinned(source, POSTBOX / "Peer.swift").split("public protocol Peer: AnyObject, PostboxCoding {", 1)[0]
    message = read_pinned(source, POSTBOX / "Message.swift").split("public struct MessageIndex: Codable, Comparable, Hashable {", 1)[0]
    coding = read_pinned(source, POSTBOX / "Coding.swift")
    buffers = coding[coding.index("private let emptyMemory ="):coding.index("enum ValueType: Int8 {")]
    (fixture / "PinnedIdentifiers.swift").write_text(peer + message + buffers)
    for name in ("ValueBoxKey.swift", "PreferencesEntry.swift"):
        (fixture / name).write_text(read_pinned(source, POSTBOX / name))
    entities = read_pinned(source, SYNCCORE / "SyncCore_TextEntitiesMessageAttribute.swift")
    (fixture / "TextEntities.swift").write_text(entities.split("public func quoteMaxLength", 1)[0].replace("import Postbox\n", ""))
    media = read_pinned(source, SYNCCORE / "SyncCore_TelegramMediaFile.swift")
    sticker = media[media.index("public enum StickerPackReference"):media.index("    init(flatBuffersObject: TelegramCore_StickerPackReference")]
    (fixture / "StickerPack.swift").write_text("import Foundation\n" + sticker + "}\n")
    for name in ("EditedMessageAttribute", "ChannelMessageStateVersionAttribute"):
        text = read_pinned(source, SYNCCORE / f"SyncCore_{name}.swift")
        (fixture / f"{name}.swift").write_text(text.split("public extension Message", 1)[0].replace("import Postbox\n", ""))
    archive = (work / POSTBOX / "LocalMessageArchive.swift").read_text().split("struct LocalMessageArchive {", 1)[0]
    (fixture / "ArchiveTypes.swift").write_text(archive)
    for path in (SYNC / "LocalArchiveCapture.swift", POSTBOX / "LocalArchiveCaptureSettings.swift"):
        (fixture / path.name).write_text((work / path).read_text().replace("import Postbox\n", ""))
    executable = directory / "capture-tests"
    command = ["xcrun", "swiftc", "-module-cache-path", str(directory / "cache")]
    if os.environ.get("GERGRAM_TEST_ASAN") == "1":
        command.append("-sanitize=address")
    subprocess.run([
        *command, *map(str, sorted(fixture.glob("*.swift"))),
        str(FIXTURE / "Support.swift"), str(FIXTURE / "CaptureTests.swift"),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Unmodified pinned Telegram-iOS checkout or equivalent source tree")
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="gergram-local-archive-capture-") as scratch:
        directory = Path(scratch)
        work = directory / "patched"
        apply_patches(arguments.source.resolve(), work)
        run_preparation_fixture(directory)
        run_capture_fixture(arguments.source.resolve(), work, directory)
