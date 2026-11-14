import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--signal-package', type=Path, default=root / 'submodules/telegram-ios/submodules/SSignalKit')
parser.add_argument('--sanitize', choices=['address'])
args = parser.parse_args()
chat = root / 'packages/ChatUI/Sources/ChatUI'
menu = (chat / 'MessageReadMenuItem.swift').read_text()
presence = (root / 'packages/TelegramUtils/Sources/TelegramUtils/PresenceStrings.swift').read_text()
fixture = Path(__file__).with_name('ReadReceiptPrecisionTests.swift').read_text()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


for marker, production in {
    '__SHORT_TIME__': section(presence, 'public func stringForShortTimestamp', 'public func stringForDuration'),
    '__RELATIVE_TIME__': section(menu, 'public func stringForRelativeTimestamp', 'private final class ReadTimestampView'),
    '__PRIVATE_TEXT__': section(menu, '        public func text(_ message:', '\n    }'),
    '__PRECISION_PROPERTIES__': section(menu, '    private var timestampPrecisionDisposable:', '    fileprivate var state:'),
    '__VISIBLE_TEXT__': section(menu, '    fileprivate var visibleText:', '    fileprivate private(set) var hiddenParticipants:'),
    '__PRECISION_SUBSCRIPTION__': section(menu, '        if message.id.peerId.namespace == Namespaces.Peer.CloudUser {\n            timestampPrecisionDisposable', '        self.load()'),
    '__PARTICIPANT_TEXT__': section(menu, '    fileprivate var timestampText:', '    override var accessibilityValue:'),
}.items():
    fixture = fixture.replace(marker, production)

formatters = (chat / 'ChatDisplayTimestamp.swift').read_text().replace('import TelegramUtils\n', '')
with tempfile.TemporaryDirectory(prefix='gergram-read-receipt-precision-') as directory:
    directory = Path(directory)
    (directory / 'Tests').mkdir()
    (directory / 'Tests/ReadReceiptPrecisionTests.swift').write_text(fixture + '\n' + formatters)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ReadReceiptPrecision", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + json.dumps(str(args.signal_package.resolve())) + ''')],
    targets: [.testTarget(name: "ReadReceiptPrecisionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    env = os.environ.copy()
    env['CLANG_MODULE_CACHE_PATH'] = str(directory / 'clang-cache')
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(directory / 'swift-cache')
    subprocess.run(command, check=True, env=env)
