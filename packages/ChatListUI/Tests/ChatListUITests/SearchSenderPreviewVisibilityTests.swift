import Postbox
import TelegramCore
import XCTest
@testable import ChatListUI

final class SearchSenderPreviewVisibilityTests: XCTestCase {
    private let account = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))
    private let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(50))
    private let forum = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(50))

    func testMatchesAreProjectedByTheirFullIdentity() {
        let sender = user(1)
        let other = user(2)
        let forwarded = user(3)
        let bot = user(4)
        let first = message(1, in: group, author: sender, forwarded: forwarded, bot: bot.id)
        let second = message(1, in: forum, author: other)
        let third = message(2, in: group, author: other)
        let matches = [first, second, third]
        let visibility = SearchSenderPreviewVisibility(messages: matches, accountPeerId: account)

        for id in [sender.id, forwarded.id, bot.id] {
            XCTAssertTrue(visibility.hidesPreview(first.id, revealed: [], hidden: [id]))
            XCTAssertFalse(visibility.hidesPreview(second.id, revealed: [], hidden: [id]))
            XCTAssertFalse(visibility.hidesPreview(third.id, revealed: [], hidden: [id]))
        }
        XCTAssertEqual(visibility.participatingSenders(revealed: []), [sender.id, other.id, forwarded.id, bot.id])
        XCTAssertEqual(matches.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(matches.map(\.text), ["Search match", "Search match", "Search match"])
    }

    func testRevealAppliesOnlyToTheSelectedDialogAndUnblockRestoresPreview() {
        let sender = user(1)
        let first = message(1, in: group, author: sender)
        let second = message(1, in: forum, author: sender)
        let visibility = SearchSenderPreviewVisibility(messages: [first, second], accountPeerId: account)

        XCTAssertFalse(visibility.hidesPreview(first.id, revealed: [group], hidden: [sender.id]))
        XCTAssertTrue(visibility.hidesPreview(second.id, revealed: [group], hidden: [sender.id]))
        XCTAssertFalse(visibility.hidesPreview(second.id, revealed: [], hidden: []))
        XCTAssertEqual(visibility.participatingSenders(revealed: [group]), [sender.id])
        XCTAssertTrue(visibility.participatingSenders(revealed: [group, forum]).isEmpty)
    }

    func testDirectChatsAndOutgoingMatchesKeepTheirPreview() {
        let sender = user(1)
        let direct = message(1, in: sender.id, author: sender)
        let outgoing = message(2, in: group, author: user(100), forwarded: sender, incoming: false)
        let saved = message(3, in: account, author: sender)
        let visibility = SearchSenderPreviewVisibility(messages: [direct, outgoing, saved], accountPeerId: account)

        XCTAssertTrue(visibility.participatingSenders(revealed: []).isEmpty)
        for item in [direct, outgoing, saved] {
            XCTAssertFalse(visibility.hidesPreview(item.id, revealed: [], hidden: [sender.id]))
        }
    }

    private func user(_ id: Int64) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func message(_ id: Int32, in peerId: PeerId, author: Peer, forwarded: Peer? = nil, bot: PeerId? = nil, incoming: Bool = true) -> Message {
        let forwardInfo = forwarded.map {
            MessageForwardInfo(author: $0, source: nil, sourceMessageId: nil, date: id, authorSignature: nil, psaType: nil, flags: [])
        }
        return Message(
            stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id,
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo,
            author: author, text: "Search match", attributes: bot.map { [InlineBotMessageAttribute(peerId: $0, title: nil)] } ?? [], media: [],
            peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:],
            associatedThreadInfo: nil, associatedStories: [:]
        )
    }
}
