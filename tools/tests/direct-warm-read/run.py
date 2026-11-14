import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
sources = root / 'packages/TelegramMedia/Sources'
parser = argparse.ArgumentParser()
parser.add_argument('--signal-package', type=Path, default=root / 'submodules/telegram-ios/submodules/SSignalKit')
parser.add_argument('--sanitize', choices=['address', 'thread'])
args = parser.parse_args()
source = (sources / 'ChunkMediaPlayerDirectFetchSourceImpl.swift').read_text()
state = source.index('        var attemptSynchronousReads: Bool?')
lookahead = source.index('        self.lookahead = FFMpegLookahead(', state)
read_argument = '            getDataInRange: '
read = source.index(read_argument, lookahead)
next_argument = source.index('            isDataCachedInRange:', read)
fixture = Path(__file__).with_name('DirectWarmReadTests.swift').read_text()
fixture = fixture.replace('__READ_STATE__', source[state:lookahead].rstrip())
fixture = fixture.replace('__READ_CLOSURE__', source[read + len(read_argument):next_argument].strip().removesuffix(','))
start_subscribe = source.index('func subscribeDirectMediaRead(')
end_subscribe = source.index('private func FFMpegLookaheadReader_readPacketCallback')
fixture = fixture.replace('__SUBSCRIBE__', source[start_subscribe:end_subscribe])

with tempfile.TemporaryDirectory(prefix='gergram-direct-warm-read-') as scratch:
    directory = Path(scratch)
    tests = directory / 'Tests'
    tests.mkdir()
    (tests / 'DirectWarmReadTests.swift').write_text(fixture)
    shutil.copyfile(sources / 'DirectMediaReadWaiter.swift', tests / 'DirectMediaReadWaiter.swift')
    dependency = json.dumps(str(args.signal_package.resolve()))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "DirectWarmRead", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + dependency + ''')],
    targets: [.testTarget(name: "DirectWarmReadTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(directory / 'clang-cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(directory / 'swift-cache'))
    subprocess.run(command, env=env, check=True)
