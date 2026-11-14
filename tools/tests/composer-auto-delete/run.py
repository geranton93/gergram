import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
chat = root / 'packages/ChatUI/Sources/ChatUI'
parser = argparse.ArgumentParser()
parser.add_argument('--signal-package', type=Path, default=root / 'submodules/telegram-ios/submodules/SSignalKit')
parser.add_argument('--sanitize', choices=['address'])
args = parser.parse_args()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


actions = (chat / 'ChatInputActionsView.swift').read_text()
preferences = (root / 'packages/InAppSettings/Sources/InAppSettings/ComposerAutoDeleteButtonPreferences.swift').read_text()
fixture = Path(__file__).with_name('ComposerAutoDeleteTests.swift').read_text()
substitutions = {
    '__ROUTE__': section(actions, '    private enum AutoDeleteButtonRoute:', '    public let chatInteraction:'),
    '__BIND__': section(actions, '        autoDeleteButtonPreferenceDisposable.set(', '\n    }'),
    '__UPDATE__': section(actions, '    private func canHideAutoDeleteButton(', '    private func updateSecretTimerImage('),
    '__WIDTH__': section(actions, '    private var extraButtons:', '    public func updateLayout(size:'),
}
for marker, code in substitutions.items():
    fixture = fixture.replace(marker, code)

with tempfile.TemporaryDirectory(prefix='gergram-composer-auto-delete-') as scratch:
    directory = Path(scratch)
    tests = directory / 'Tests'
    tests.mkdir()
    (tests / 'ComposerAutoDeleteTests.swift').write_text(fixture + '\n' + preferences)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ComposerAutoDelete", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + json.dumps(str(args.signal_package.resolve())) + ''')],
    targets: [.testTarget(name: "ComposerAutoDeleteTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    env = os.environ.copy()
    env['CLANG_MODULE_CACHE_PATH'] = str(directory / 'clang-cache')
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(directory / 'swift-cache')
    subprocess.run(command, check=True, env=env)
