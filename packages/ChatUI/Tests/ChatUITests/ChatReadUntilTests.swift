import ChatModeTypes
import Postbox
import TelegramContext
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatReadUntilTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func user(_ id: Int64 = 2, name: String? = "Sender") -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil,
                     firstName: name, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil,
                     restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil,
                     backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil,
                     verificationIconFileId: nil)
    }

    private func channel(flags: TelegramChannelFlags = [], participation: TelegramChannelParticipationStatus = .member) -> TelegramChannel {
        TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1)), accessHash: nil,
                        title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: participation,
                        info: .broadcast(.init(flags: [])), flags: flags, restrictionInfo: nil, adminRights: nil, bannedRights: nil,
                        defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
                        profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil,
                        subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func presentation(_ peer: Peer, mode: ChatMode = .history) -> ChatPresentationInterfaceState {
        ChatPresentationInterfaceState(chatLocation: .peer(peer.id), chatMode: mode).updatedPeer { _ in peer }
    }

    private func message(_ id: Int32, peer: Peer, namespace: MessageId.Namespace = Namespaces.Message.Cloud,
                         album: Int64? = nil, thread: Int64? = nil, timestamp: Int32 = 100,
                         flags: MessageFlags = [.Incoming]) -> Message {
        Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: namespace, id: id),
                globallyUniqueId: nil, groupingKey: album, groupInfo: nil, threadId: thread, timestamp: timestamp,
                flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
                author: peer, text: "Message", attributes: [], media: [], peers: SimpleDictionary(),
                associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:],
                associatedThreadInfo: nil, associatedStories: [:])
    }

    func testOnlyOrdinaryCurrentHistorySupportsTheAction() {
        let direct = user()
        XCTAssertEqual(ChatReadUntilPolicy.peer(in: presentation(direct), accountPeerId: accountId)?.id, direct.id)
        let member = channel()
        XCTAssertEqual(ChatReadUntilPolicy.peer(in: presentation(member), accountPeerId: accountId)?.id, member.id)
        XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(user(1)), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(user(name: nil)), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(channel(participation: .left)), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(channel(flags: [.isForum])), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(channel(flags: [.isMonoforum])), accountPeerId: accountId))
        for mode in [ChatMode.preview, .scheduled, .pinned] {
            XCTAssertNil(ChatReadUntilPolicy.peer(in: presentation(direct, mode: mode), accountPeerId: accountId))
        }
        let state = presentation(direct)
        XCTAssertNil(ChatReadUntilPolicy.peer(in: state.withSelectionState(), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: state.withUpdatedIsNotAccessible(true), accountPeerId: accountId))
        XCTAssertNil(ChatReadUntilPolicy.peer(in: state.withUpdatedChatLocation(.peer(user(3).id)), accountPeerId: accountId))
        let thread = ChatLocation.makeSaved(accountId, threadId: 12)
        XCTAssertNil(ChatReadUntilPolicy.peer(in: state.withUpdatedChatLocation(thread), accountPeerId: accountId))
    }

    func testTargetRejectsOutgoingLocalInvalidAndCrossTopicMessages() {
        let peer = user()
        let state = presentation(peer)
        let eligible = message(1, peer: peer)
        XCTAssertEqual(ChatReadUntilPolicy.target(message: eligible, album: nil, presentation: state, accountPeerId: accountId)?.id, eligible.id)
        let invalid = [message(0, peer: peer), message(Int32.max, peer: peer), message(2, peer: user(3)), message(2, peer: peer, namespace: Namespaces.Message.Local),
                       message(2, peer: peer, thread: 10), message(2, peer: peer, flags: []),
                       message(2, peer: peer, flags: [.Incoming, .Failed])]
        for target in invalid {
            XCTAssertNil(ChatReadUntilPolicy.target(message: target, album: nil, presentation: state, accountPeerId: accountId))
        }
    }

    func testAlbumUsesTheGreatestServerIdAndRejectsUnrelatedMembers() {
        let peer = user()
        let state = presentation(peer)
        let source = message(3, peer: peer, album: 7, timestamp: 300)
        let endpoint = message(5, peer: peer, album: 7, timestamp: 100)
        XCTAssertEqual(ChatReadUntilPolicy.target(message: source, album: [endpoint, source], presentation: state, accountPeerId: accountId)?.id, endpoint.id)
        for album in [[endpoint], [source, message(5, peer: peer, album: 8)], [source, message(5, peer: user(3), album: 7)],
                      [source, message(5, peer: peer, album: 7, flags: [])]] {
            XCTAssertNil(ChatReadUntilPolicy.target(message: source, album: album, presentation: state, accountPeerId: accountId))
        }
    }

    func testAssociatedMigrationAndInaccessibleChannelsAreExcluded() {
        let peer = channel()
        let state = presentation(peer)
        let migration = ChannelMigrationReference(maxMessageId: message(5, peer: user()).id)
        let migrated = CachedChannelData().withUpdatedMigrationReference(migration)
        XCTAssertNil(ChatReadUntilPolicy.peer(in: state.withUpdatedCachedData(migrated), accountPeerId: accountId))
        XCTAssertFalse(ChatReadUntilPolicy.supports(CachedChannelData().withUpdatedIsNotAccessible(true)))
    }

}
