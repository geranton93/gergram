import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
ios = root / 'submodules/telegram-ios'
pin = '24638bc69bd083981b178dd1e7f921eebbf7fc46'
path = 'submodules/TelegramCore/Sources/PendingMessages/PendingMessageUploadedContent.swift'
blob = '6585a8aa2e516848e260eedea23ce2d0969ca564'
patch = root / 'scripts/telegram-ios-repeat-photo-reference.patch'

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ios, help='Pinned unmodified Telegram-iOS source tree')
parser.add_argument('--signal-package', type=Path, default=ios / 'submodules/SSignalKit')
parser.add_argument('--sanitize', choices=['address'])
args = parser.parse_args()

source = args.source.resolve()
if (source / '.git').exists():
    original = subprocess.check_output(['git', '-C', str(source), 'show', f'{pin}:{path}'])
else:
    original = (source / path).read_bytes()
assert hashlib.sha1(f'blob {len(original)}\0'.encode() + original).hexdigest() == blob

with tempfile.TemporaryDirectory(prefix='gergram-repeat-photo-') as scratch:
    directory = Path(scratch)
    patched = directory / 'telegram-ios'
    file = patched / path
    file.parent.mkdir(parents=True)
    file.write_bytes(original)
    subprocess.run(['git', 'init', '-q', str(patched)], check=True)
    apply = ['git', '-C', str(patched), 'apply']
    for flags in (['--check'], [], ['--reverse', '--check']):
        subprocess.run([*apply, *flags, str(patch)], check=True)
    source = file.read_text()
    start = source.index('        if peerId.namespace != Namespaces.Peer.SecretChat, let reference = image.reference')
    branch = source[start:source.index('    } else if let file = media as? TelegramMediaFile', start)]
    end = branch.rindex('        } else {')
    branch = branch[:end] + '        }\n        return .fail(.generic)\n'
    subprocess.run([*apply, '--reverse', str(patch)], check=True)
    assert file.read_bytes() == original

    tests = directory / 'Tests'
    tests.mkdir()
    fixture = Path(__file__).with_name('RepeatPhotoReferenceTests.swift').read_text().replace('__PHOTO_BRANCH__', branch)
    (tests / 'RepeatPhotoReferenceTests.swift').write_text(fixture)
    signal = json.dumps(str(args.signal_package.resolve()))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RepeatPhotoReference", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + signal + ''')],
    targets: [.testTarget(name: "RepeatPhotoReferenceTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(directory / 'clang-cache')
    environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(directory / 'swift-cache')
    subprocess.run(command, check=True, env=environment)
