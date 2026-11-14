import Postbox
import TelegramCore
import XCTest
@testable import ChatListUI

final class ForumSidebarSenderPreviewVisibilityTests: XCTestCase {
    private let forumId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(10))
    private let anotherForumId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(11))
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))

    func testSidebarRootAndEligibleTopicsUseTheirOwnMessages() throws {
        let older = user(1)
        let newer = user(2)
        let outgoing = user(100)
        let rootMessage = message(4, author: newer)
        let first = item(.forum(40), messages: [message(1, author: older)], draft: "My draft")
        let second = item(.forum(41), messages: [rootMessage, message(2, author: outgoing, incoming: false)])
        let unavailable = item(.forum(42), messages: [message(3, author: user(3))], includesThread: false)
        let items = [first, second, unavailable]
        let root = try XCTUnwrap(ForumSidebarSenderPreviewVisibility.rootPreview(in: items))
        let candidates = ForumSidebarSenderPreviewVisibility.candidates(peerId: forumId, rootMessage: root, items: items, accountPeerId: accountId)
        XCTAssertEqual(root.id, rootMessage.id)
        XCTAssertEqual(candidates, [row(.chatList(forumId)): [newer.id], row(.forum(40)): [older.id], row(.forum(41)): [newer.id]])
        XCTAssertEqual(first.draft?.text, "My draft")
        XCTAssertEqual(first.threadData?.incomingUnreadCount, 7)
        XCTAssertEqual(first.threadData?.info.title, "Topic")
        XCTAssertEqual(second.messages.count, 2)
    }

    func testChangedRowsAreSuppressedWhileUnchangedRowsKeepTheirDecision() throws {
        let first = user(1).id
        let second = user(2).id
        var visibility = ForumSidebarSenderPreviewVisibility()
        let initial = try XCTUnwrap(visibility.update(peerId: forumId, candidates: [row(.forum(40)): [first], row(.forum(41)): [second]]))
        XCTAssertTrue(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.hidesPreview(.forum(41), peerId: forumId))
        XCTAssertTrue(visibility.apply(initial, revealed: [], hidden: []))
        let replacement = try XCTUnwrap(visibility.update(peerId: forumId, candidates: [row(.forum(40)): [first], row(.forum(41)): [first]]))
        XCTAssertFalse(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.hidesPreview(.forum(41), peerId: forumId))
        XCTAssertFalse(visibility.apply(initial, revealed: [], hidden: []))
        XCTAssertNil(visibility.update(peerId: forumId, candidates: replacement.candidates))
        XCTAssertTrue(visibility.apply(replacement, revealed: [], hidden: [first]))
        XCTAssertTrue(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.hidesPreview(.forum(41), peerId: forumId))
        XCTAssertTrue(visibility.apply(replacement, revealed: [forumId], hidden: [first]))
        XCTAssertFalse(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.apply(replacement, revealed: [], hidden: [first]))
        XCTAssertTrue(visibility.apply(replacement, revealed: [], hidden: []))
        XCTAssertFalse(visibility.hidesPreview(.forum(40), peerId: forumId))
    }

    func testScopeSwitchRejectsStaleResultsEvenAfterReturningToSameForum() throws {
        let sender = user(1).id
        let candidates: ForumSidebarSenderPreviewVisibility.CandidateRows = [row(.forum(40)): [sender]]
        var visibility = ForumSidebarSenderPreviewVisibility()
        let first = try XCTUnwrap(visibility.update(peerId: forumId, candidates: candidates))
        XCTAssertTrue(visibility.apply(first, revealed: [], hidden: []))
        let second = try XCTUnwrap(visibility.update(peerId: anotherForumId, candidates: [row(.forum(40), peerId: anotherForumId): [sender]]))
        XCTAssertFalse(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.hidesPreview(.forum(40), peerId: anotherForumId))
        let current = try XCTUnwrap(visibility.update(peerId: forumId, candidates: candidates))
        XCTAssertFalse(visibility.apply(first, revealed: [], hidden: []))
        XCTAssertFalse(visibility.apply(second, revealed: [], hidden: []))
        XCTAssertTrue(visibility.hidesPreview(.forum(40), peerId: forumId))
        XCTAssertTrue(visibility.apply(current, revealed: [], hidden: []))
        let inactive = try XCTUnwrap(visibility.update(peerId: nil, candidates: [:]))
        XCTAssertFalse(visibility.apply(current, revealed: [], hidden: [sender]))
        XCTAssertFalse(visibility.apply(inactive, revealed: [], hidden: [sender]))
        XCTAssertFalse(visibility.hidesPreview(.forum(40), peerId: forumId))
    }

    private func row(_ id: EngineChatList.Item.Id, peerId: PeerId? = nil) -> ForumSidebarSenderPreviewVisibility.Row {
        return .init(id: id, peerId: peerId ?? forumId)
    }

    private func user(_ id: Int64) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func message(_ id: Int32, author: Peer, incoming: Bool = true) -> Message {
        return Message(stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: forumId, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: author, text: "Message \(id)", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func item(_ id: EngineChatList.Item.Id, messages: [Message], draft: String? = nil, includesThread: Bool = true) -> EngineChatList.Item {
        let author = user(1)
        let threadData = MessageHistoryThreadData(
            creationDate: 0, isOwnedByMe: false, author: author.id,
            info: EngineMessageHistoryThread.Info(title: "Topic", icon: nil, iconColor: 0),
            incomingUnreadCount: 7, isMarkedUnread: false, maxIncomingReadId: 0, maxKnownMessageId: 0,
            maxOutgoingReadId: 0, isClosed: false, isHidden: false,
            notificationSettings: TelegramPeerNotificationSettings.defaultSettings, isMessageFeeRemoved: false
        )
        return EngineChatList.Item(
            id: id, index: .forum(pinnedIndex: .none, timestamp: 0, threadId: 40, namespace: Namespaces.Message.Cloud, id: 0),
            messages: messages.map { EngineMessage($0) }, readCounters: nil, isMuted: false,
            draft: draft.map { EngineChatList.Draft(text: $0, entities: []) },
            threadData: includesThread ? threadData : nil, renderedPeer: EngineRenderedPeer(peer: .user(author)),
            presence: nil, hasUnseenMentions: false, hasUnseenReactions: false, hasUnseenPollVotes: false,
            forumTopicData: nil, topForumTopicItems: [], hasFailed: false, isContact: false,
            autoremoveTimeout: nil, storyStats: nil, displayAsTopicList: false,
            isPremiumRequiredToMessage: false, mediaDraftContentType: nil
        )
    }
}
