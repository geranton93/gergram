import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatUI/Sources/ChatUI/ChatVoiceContentView.swift')
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()
source = args.source.read_text()
fixture = Path(__file__).with_name('VoiceWaveformSeekTests.swift').read_text()


def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


fixture = fixture.replace('__GESTURE_STATE__', section('    private struct WaveformSeek', '    private var transcribeAudio:'))
fixture = fixture.replace('__GESTURE_EVENTS__', section('    public override func mouseDragged', '    public override func update(with media:'))
fixture = fixture.replace('__WAVEFORM_INIT__', section('        waveformView.isEventLess = true', '        addSubview(waveformView)'))
fixture = fixture.replace('__WAVEFORM_REBIND__', section('        if self.parent?.id != parent?.id', '        super.update(with:'))

with tempfile.TemporaryDirectory(prefix='voice-waveform-seek-') as directory:
    directory = Path(directory)
    test_source = directory / 'main.swift'
    test_source.write_text(fixture)
    binary = directory / 'tests'
    command = ['swiftc', '-module-cache-path', str(directory / 'module-cache')]
    if args.sanitize:
        command += ['-sanitize=address']
    subprocess.run([*command, str(test_source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
