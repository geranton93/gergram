import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
chat_ui = root / 'packages/ChatUI/Sources/ChatUI'
parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()
fixture = Path(__file__).with_name('PreviewSizeTests.swift').read_text()


def section(file_name, start, end):
    source = (chat_ui / file_name).read_text()
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


layout = 'WPArticleLayout.swift'
fixture = fixture.replace('__MEDIA_POLICY__', section(layout, 'extension SocialPostPreview', 'public class WPArticleLayout'))
fixture = fixture.replace('__HISTORY_SIZE__', section(layout, '    private let mediaTypes', '    public override func measure'))
fixture = fixture.replace('__COMPOSER_SIZE__', section('ChatInputAccessory.swift', '            let previewURL =', '            container.contextMenu ='))

with tempfile.TemporaryDirectory(prefix='social-preview-size-') as directory:
    directory = Path(directory)
    test_source = directory / 'main.swift'
    test_source.write_text(fixture)
    executable = directory / 'tests'
    command = ['swiftc', '-module-cache-path', str(directory / 'module-cache')]
    if args.sanitize:
        command += ['-sanitize=address']
    subprocess.run([*command, str(test_source), str(chat_ui / 'SocialPostPreview.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
