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
source = (root / 'packages/SettingsUI/Sources/SettingsUI/DockControl.swift').read_text()
production = source[source.index('public final class DockControl'):]
fixture = Path(__file__).with_name('DockControlTests.swift').read_text()

with tempfile.TemporaryDirectory(prefix='gergram-dock-control-') as scratch:
    directory = Path(scratch)
    (directory / 'Tests').mkdir()
    (directory / 'Tests/DockControlTests.swift').write_text(fixture + '\n' + production)
    dependency = json.dumps(str(args.signal_package.resolve()))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "DockControl", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + dependency + ''')],
    targets: [.testTarget(name: "DockControlTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(directory / 'clang-cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(directory / 'swift-cache'))
    subprocess.run(command, env=env, check=True)
