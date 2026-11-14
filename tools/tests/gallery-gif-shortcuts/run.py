import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
gallery = root / 'packages/GalleryUI/Sources/GalleryUI'
parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


viewer = (gallery / 'GalleryViewer.swift').read_text()
space = viewer.index('}, with:self, for: .Space)')
registration_start = viewer.rfind('        window.setGalleryKeyHandler(', 0, space)
registration = viewer[registration_start:viewer.index('        window.setGalleryKeyHandler(', viewer.index('for: .K)', space))]
shortcut = section(viewer, '    private func handleGIFPlaybackShortcut(', '    private func showControlsPopoverReady(')
gif_item = (gallery / 'MGalleryGIFItem.swift').read_text()
toggle = section(gif_item, '    public override func togglePlayerOrPause(', '    public override var status:')
keyboard = (gallery / 'GalleryKeyboardHandler.swift').read_text()
keyboard = keyboard[keyboard.index('extension Window'):].replace('extension Window', 'extension TestWindow', 1)
fixture = Path(__file__).with_name('GalleryGIFShortcutTests.swift').read_text()
for marker, code in [
    ('__REGISTRATION__', registration),
    ('__SHORTCUT__', shortcut),
    ('__TOGGLE__', toggle),
    ('__KEYBOARD__', keyboard),
]:
    fixture = fixture.replace(marker, code)

with tempfile.TemporaryDirectory(prefix='gallery-gif-shortcuts-') as directory:
    directory = Path(directory)
    test_source = directory / 'main.swift'
    test_source.write_text(fixture)
    binary = directory / 'tests'
    command = ['swiftc', '-module-cache-path', str(directory / 'module-cache')]
    if args.sanitize:
        command += ['-sanitize=address']
    subprocess.run([*command, str(test_source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
