import Postbox
import TelegramCore
import XCTest
@testable import ChatListUI

final class ChatListSenderPreviewVisibilityTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))
    private let roomId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(55))
    private let forumId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(56))

    func testPreviewCandidatesIncludeDirectForwardedAndInlineBotSources() {
        let sender = user(1)
        let forwarded = user(2)
        let bot = user(3)
        let first = message(1, peerId: roomId, author: sender, forwarded: forwarded, bot: bot.id)
        let second = message(2, peerId: roomId, author: sender, text: "Caption")
        let ids = ChatListSenderPreviewVisibility.candidates(chatPeerId: roomId, messages: [first, second], accountPeerId: accountId)
        XCTAssertEqual(ids, [sender.id, forwarded.id, bot.id])
        XCTAssertTrue(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: roomId, candidates: ids, revealed: [], hidden: [forwarded.id]))
    }

    func testDirectChatsAndOutgoingMessagesKeepTheirPreview() {
        let sender = user(1)
        let bot = user(2)
        let direct = message(1, peerId: sender.id, author: sender, bot: bot.id)
        let outgoing = message(2, peerId: roomId, author: user(100), bot: bot.id, incoming: false)
        XCTAssertTrue(ChatListSenderPreviewVisibility.candidates(chatPeerId: sender.id, messages: [direct], accountPeerId: accountId).isEmpty)
        XCTAssertTrue(ChatListSenderPreviewVisibility.candidates(chatPeerId: roomId, messages: [outgoing], accountPeerId: accountId).isEmpty)
    }

    func testRevealAffectsOnlyItsDialogAndCanBeReversed() {
        let ids: Set<PeerId> = [user(1).id]
        XCTAssertFalse(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: roomId, candidates: ids, revealed: [roomId], hidden: ids))
        XCTAssertTrue(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: forumId, candidates: ids, revealed: [roomId], hidden: ids))
        XCTAssertTrue(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: roomId, candidates: ids, revealed: [], hidden: ids))
        XCTAssertFalse(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: roomId, candidates: ids, revealed: [], hidden: []))
        let rows: ChatListSenderPreviewVisibility.CandidateRows = [
            .init(id: .forum(1), peerId: forumId): ids,
            .init(id: .forum(2), peerId: forumId): ids.union([user(2).id]),
            .init(id: .chatList(roomId), peerId: roomId): [user(3).id]
        ]
        XCTAssertEqual(ChatListSenderPreviewVisibility.participatingSenders(in: rows, revealed: [forumId]), [user(3).id])
        XCTAssertEqual(ChatListSenderPreviewVisibility.participatingSenders(in: rows, revealed: []), [user(1).id, user(2).id, user(3).id])
    }

    func testHiddenAlbumSuppressesCaptionWithoutMutatingOriginalPreviewOrder() {
        let sender = user(1)
        let first = message(1, peerId: roomId, author: sender)
        let caption = message(2, peerId: roomId, author: sender, text: "Caption")
        XCTAssertNil(ChatListSenderPreviewVisibility.previewMessage([first, caption], hidden: true))
        XCTAssertEqual(ChatListSenderPreviewVisibility.previewMessage([first, caption], hidden: false)?.id, caption.id)
        XCTAssertEqual(ChatListSenderPreviewVisibility.previewMessage([first], hidden: false)?.id, first.id)
        XCTAssertEqual([first, caption].map(\.id.id), [1, 2])
    }

    func testArchiveUsesTheSingleChatTopMessageAndRetainsOriginalMetadata() throws {
        let sender = user(1)
        let forwarded = user(2)
        let bot = user(3)
        let top = message(8, peerId: forumId, author: sender, forwarded: forwarded, bot: bot.id, text: "Hidden archive preview")
        let archived = archive([forumId], top: top, unreadCount: 7)
        let preview = try XCTUnwrap(ChatListSenderPreviewVisibility.archivePreview(for: archived, accountPeerId: accountId))

        XCTAssertEqual(preview.peerId, forumId)
        XCTAssertEqual(preview.senders, [sender.id, forwarded.id, bot.id])
        XCTAssertTrue(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: preview.peerId, candidates: preview.senders, revealed: [roomId], hidden: [bot.id]))
        XCTAssertFalse(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: preview.peerId, candidates: preview.senders, revealed: [forumId], hidden: [bot.id]))
        XCTAssertFalse(ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: preview.peerId, candidates: preview.senders, revealed: [], hidden: []))
        XCTAssertEqual(archived.topMessage?.id, top.id)
        XCTAssertEqual(archived.topMessage?.timestamp, top.timestamp)
        XCTAssertEqual(archived.topMessage?.text, "Hidden archive preview")
        XCTAssertEqual(archived.items.map(\.isUnread), [true])
        XCTAssertEqual(archived.unreadCount, 7)
    }

    func testArchiveSkipsItsTitleListsAndIneligibleMessages() {
        let sender = user(1)
        let olderPeer = user(2)
        let incoming = message(1, peerId: forumId, author: sender)
        let direct = message(2, peerId: sender.id, author: sender)
        let outgoing = message(3, peerId: forumId, author: user(100), incoming: false)
        let cases = [
            archive([], top: incoming),
            archive([forumId, olderPeer.id], top: incoming),
            archive([forumId]),
            archive([roomId], top: incoming),
            archive([sender.id], top: direct),
            archive([forumId], top: outgoing)
        ]
        for archived in cases {
            XCTAssertNil(ChatListSenderPreviewVisibility.archivePreview(for: archived, accountPeerId: accountId))
        }
    }

    private func archive(_ peerIds: [PeerId], top: Message? = nil, unreadCount: Int = 0) -> EngineChatList.GroupItem {
        return .init(id: .archive, topMessage: top.flatMap { EngineMessage($0) }, items: peerIds.map {
            .init(peer: EngineRenderedPeer(RenderedPeer(peerId: $0, peers: SimpleDictionary(), associatedMedia: [:])), isUnread: true)
        }, unreadCount: unreadCount)
    }

    private func user(_ id: Int64) -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func message(_ id: Int32, peerId: PeerId, author: Peer, forwarded: Peer? = nil, bot: PeerId? = nil, text: String = "", incoming: Bool = true) -> Message {
        let forwardInfo = forwarded.map {
            MessageForwardInfo(author: $0, source: nil, sourceMessageId: nil, date: id, authorSignature: nil, psaType: nil, flags: [])
        }
        return Message(
            stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id),
            globallyUniqueId: nil, groupingKey: 101, groupInfo: nil, threadId: nil, timestamp: id,
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo,
            author: author, text: text, attributes: bot.map { [InlineBotMessageAttribute(peerId: $0, title: nil)] } ?? [], media: [],
            peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:],
            associatedThreadInfo: nil, associatedStories: [:]
        )
    }
}
