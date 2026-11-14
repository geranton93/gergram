import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source_dir = root / 'packages/ChatUI/Sources/ChatUI'
parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()
source = (source_dir / 'ChatMessageShotAction.swift').read_text()
fixture = Path(__file__).with_name('ReplyTests.swift').read_text()


def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


fixture = fixture.replace('__TYPES__', section('    private struct ReplyExcerpt', '    private typealias PreparedShot'))
fixture = fixture.replace('__RESOLVE_REPLY__', section('    private static func replyReference', '    private static func supportsSnapshot'))
fixture = fixture.replace('__RENDER_REPLY__', section('    private static func renderReply', '    private static func rows'))
strings = (root / 'Telegram-Mac/en.lproj/Localizable.strings').read_text(encoding='utf-16')
for key in ['Title', 'Text']:
    full_key = f'Gergram.Chat.MessageShotExternalReply{key}'
    definition = next(line for line in strings.splitlines() if line.startswith(f'"{full_key}" = '))
    fixture = fixture.replace(f'__EXTERNAL_{key.upper()}__', definition.split(' = ', 1)[1].removesuffix(';'))

with tempfile.TemporaryDirectory(prefix='message-shot-replies-') as directory:
    directory = Path(directory)
    test_source = directory / 'main.swift'
    test_source.write_text(fixture)
    binary = directory / 'tests'
    command = ['swiftc', '-module-cache-path', str(directory / 'module-cache')]
    if args.sanitize:
        command += ['-sanitize=address']
    subprocess.run([*command, str(test_source), str(source_dir / 'MessageShotRenderer.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
