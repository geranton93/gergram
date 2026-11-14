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
registration_end = viewer.index('            self.pager.toggleFullScreen()', space)
registration = viewer[registration_start:viewer.rfind('        window.setGalleryKeyHandler(', space, registration_end)]
shortcut = section(viewer, '    private func handleGIFPlaybackShortcut(', '    private func showControlsPopoverReady(')
gif_item = (gallery / 'MGalleryGIFItem.swift').read_text()
gif_controls = section(gif_item, '    public override func togglePlayerOrPause(', '    public override var status:')
player = (root / 'packages/TelegramMedia/Sources/MediaPlayer.swift').read_text()
player_context_seek = section(player, '    fileprivate func seek(timestamp: Double) {', '    fileprivate func seek(timestamp: Double, action:')
player_seek = section(player, '    public func seekVideo(', '    public func seek(timestamp: Double, play:')
loop_finish = section(player, '                case let .loop(f):', '                case .stop:')
restore_timestamp = section(player, '    private static func videoRestoreTimestamp(', '    private func seekingCompleted(')
keyboard = (gallery / 'GalleryKeyboardHandler.swift').read_text()
keyboard = keyboard[keyboard.index('extension Window'):].replace('extension Window', 'extension TestWindow', 1)
fixture = Path(__file__).with_name('GalleryGIFShortcutTests.swift').read_text()
for marker, code in [
    ('__REGISTRATION__', registration),
    ('__SHORTCUT__', shortcut),
    ('__GIF_CONTROLS__', gif_controls),
    ('__PLAYER_CONTEXT_SEEK__', player_context_seek),
    ('__PLAYER_SEEK__', player_seek),
    ('__LOOP_FINISH__', loop_finish),
    ('__RESTORE_TIMESTAMP__', restore_timestamp),
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
