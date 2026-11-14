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


view = (chat / 'ChatInputView.swift').read_text()
attach = (chat / 'ChatInputAttachView.swift').read_text()
settings = root / 'packages/InAppSettings/Sources/InAppSettings'
preferences = [settings / name for name in (
    'ComposerAIToolsButtonPreferences.swift',
    'ComposerRichTextEditorPreferences.swift',
)]
fixture = Path(__file__).with_name('ComposerAIToolsTests.swift').read_text()
substitutions = {
    '__ELIGIBILITY__': section(view, '    private func isComposerAIEditorEligible(', '    public override func layout() {\n        super.layout()\n        updateLayout(transition:'),
    '__MENU_BINDING__': section(view, '        attachView.canOpenAIEditorFromMenu =', '\n    }'),
    '__AI_LAYOUT__': section(view, '        let isAIEditorEligible =', '\n        let sendAsInset:'),
    '__RICH_LAYOUT__': section(view, '        let showExpand =', '\n        if showExpand {'),
    '__PREFERENCE_BINDING__': section(view, '        composerEditorControlsDisposable.set(', '\n    }'),
    '__RICH_MENU_ELIGIBILITY__': section(attach, '    var canOpenRichTextEditorFromMenu: Bool {', '    public private(set) var isMorphHeld'),
    '__RICH_MENU_ITEM__': section(attach, '                if #available(macOS 12, *), self.canOpenRichTextEditorFromMenu {', '\n            }'),
    '__MENU_ITEM__': section(attach, '            if self.canOpenAIEditorFromMenu?() == true {', '            if !items.isEmpty {'),
}
for marker, code in substitutions.items():
    fixture = fixture.replace(marker, code)
fixture += '\n' + '\n'.join(path.read_text() for path in preferences)

with tempfile.TemporaryDirectory(prefix='gergram-composer-ai-tools-') as scratch:
    directory = Path(scratch)
    tests = directory / 'Tests'
    tests.mkdir()
    (tests / 'ComposerAIToolsTests.swift').write_text(fixture)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ComposerAITools", platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: ''' + json.dumps(str(args.signal_package.resolve())) + ''')],
    targets: [.testTarget(name: "ComposerAIToolsTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    command = ['swift', 'test', '--package-path', str(directory), '--manifest-cache', 'none', '--disable-sandbox', '--jobs', '4']
    if args.sanitize:
        command.extend(['--sanitize', args.sanitize])
    env = os.environ.copy()
    env['CLANG_MODULE_CACHE_PATH'] = str(directory / 'clang-cache')
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(directory / 'swift-cache')
    subprocess.run(command, check=True, env=env)
