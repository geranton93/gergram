import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', action='store_true')
args = parser.parse_args()


def section(path, start, end):
    source = (root / path).read_text()
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


chat = 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
profile = 'packages/PeerInfoUI/Sources/PeerInfoUI'
policy = (root / 'packages/MessageUtils/Sources/MessageUtils/DiscussionLinkedChannel.swift').read_text()
policy = '\n'.join(line for line in policy.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('DiscussionLinkedChannelTests.swift').read_text()
substitutions = {
    '__POLICY__': policy,
    '__CHAT__': section(chat, '                if !self.isAdChat, peerView.peerId == peerId,', '                if let notificationSettings'),
    '__PROFILE__': section(f'{profile}/PeerInfoHeadItem.swift', '        if item.threadId == nil, !item.editing, !arguments.isAd,', '        if access.canAddMembers'),
    '__PROFILE_MORE__': section(f'{profile}/PeerInfoHeadItem.swift', '    if items.count > rowItemsCount || !moreItems.isEmpty {', '    return items'),
    '__PROFILE_ACTION__': section(f'{profile}/PeerInfoController.swift', '        _groupArguments.openDiscussionLinkedChannel =', '        _userArguments ='),
}
for marker, code in substitutions.items():
    fixture = fixture.replace(marker, code)

with tempfile.TemporaryDirectory(prefix='discussion-linked-channel-') as directory:
    directory = Path(directory)
    test_source = directory / 'main.swift'
    test_source.write_text(fixture)
    binary = directory / 'tests'
    command = ['swiftc', '-module-cache-path', str(directory / 'module-cache')]
    if args.sanitize:
        command += ['-sanitize=address']
    subprocess.run([*command, str(test_source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
