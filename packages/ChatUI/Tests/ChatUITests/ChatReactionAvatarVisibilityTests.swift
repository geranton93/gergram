import Postbox
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatReactionAvatarVisibilityTests: XCTestCase {
    private let account = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(5))
    private let reactor = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(11))
    private let author = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(12))
    private let anonymous = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(11))
    private let room = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(21))
    private let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(22))

    func testKnownBlockedReactorNeverBecomesATranscriptSender() {
        let candidates = ChatBlockedSenderVisibility.Candidates(messageSenders: [author], reactionAvatars: [reactor, author, anonymous])
        XCTAssertEqual(candidates.peerIds, [author, reactor, anonymous])
        XCTAssertEqual(candidates.blockedPeerIds, [author, reactor])
        let projected = candidates.project(knownBlocked: [reactor, account], locallyHidden: [anonymous])
        XCTAssertTrue(projected.messageSenders.isEmpty)
        XCTAssertEqual(projected.reactionAvatars, [reactor, anonymous])
        let blockedAuthor = candidates.project(knownBlocked: [author], locallyHidden: [])
        XCTAssertEqual(blockedAuthor.messageSenders, [author])
        XCTAssertEqual(blockedAuthor.reactionAvatars, [author])
    }

    func testTemporaryRevealBypassesBothSourcesAndLocalRulesWorkWithoutBlockPreference() {
        typealias Candidates = ChatBlockedSenderVisibility.Candidates
        XCTAssertFalse(Candidates.shouldFilter(hidesBlocked: false, showsFilteredSenders: false, locallyHidden: []))
        XCTAssertTrue(Candidates.shouldFilter(hidesBlocked: true, showsFilteredSenders: false, locallyHidden: []))
        XCTAssertTrue(Candidates.shouldFilter(hidesBlocked: false, showsFilteredSenders: false, locallyHidden: [anonymous]))
        XCTAssertFalse(Candidates.shouldFilter(hidesBlocked: true, showsFilteredSenders: true, locallyHidden: [anonymous]))
    }

    func testAnyHiddenAvatarUsesTheUnmodifiedReactionCountAsFallback() {
        let native = MessageReaction(value: .builtin("👍"), count: 3, chosenOrder: 0)
        let data = [recent(native.value, account), recent(native.value, reactor), recent(native.value, author)]
        let peers: [PeerId: Peer] = [account: user(account), reactor: user(reactor), author: user(author)]
        let resolved = ChatReactionAvatarVisibility.resolvedPeers(for: native, recentPeers: data, resolve: { peers[$0] })
        XCTAssertEqual(resolved.map(\.id), [account, reactor, author])
        XCTAssertEqual(ChatReactionAvatarVisibility.visiblePeers(resolved, excluding: [anonymous]).map(\.id), resolved.map(\.id))
        XCTAssertNil(ChatReactionAvatarVisibility.countText(native, hasAvatars: !resolved.isEmpty))
        let filtered = ChatReactionAvatarVisibility.visiblePeers(resolved, excluding: [reactor])
        XCTAssertTrue(filtered.isEmpty)
        XCTAssertEqual(ChatReactionAvatarVisibility.countText(native, hasAvatars: !filtered.isEmpty), "3")
        XCTAssertEqual(native.count, 3)
        XCTAssertEqual(native.chosenOrder, 0)
    }

    func testOnlyCompleteSmallReactionDataCanIdentifyAvatars() {
        let thumbs = MessageReaction(value: .builtin("👍"), count: 2, chosenOrder: nil)
        let stars = MessageReaction(value: .stars, count: 2, chosenOrder: nil)
        let peers: [PeerId: Peer] = [reactor: user(reactor), author: user(author), account: user(account)]
        XCTAssertFalse(ChatReactionAvatarVisibility.eligibleReactionCounts([thumbs, stars]))
        XCTAssertFalse(ChatReactionAvatarVisibility.eligibleReactionCounts([.init(value: .stars, count: -1, chosenOrder: nil)]))
        XCTAssertFalse(ChatReactionAvatarVisibility.eligibleReactionCounts([.init(value: .stars, count: .max, chosenOrder: nil), stars]))
        XCTAssertTrue(ChatReactionAvatarVisibility.eligibleReactionCounts([thumbs]))

        let missingPeer = [recent(thumbs.value, reactor), recent(thumbs.value, anonymous), recent(stars.value, author)]
        XCTAssertTrue(ChatReactionAvatarVisibility.resolvedPeers(for: thumbs, recentPeers: missingPeer, resolve: { peers[$0] }).isEmpty)
        let tooMany = [recent(thumbs.value, reactor), recent(thumbs.value, author), recent(thumbs.value, account)]
        XCTAssertTrue(ChatReactionAvatarVisibility.resolvedPeers(for: thumbs, recentPeers: tooMany, resolve: { peers[$0] }).isEmpty)
    }

    func testOnlyOrdinaryGroupMessagesContributeParticipants() {
        let thumbs = MessageReaction(value: .builtin("👍"), count: 2, chosenOrder: nil)
        let reactions = ReactionsMessageAttribute(canViewList: true, isTags: false, reactions: [thumbs], recentPeers: [
            recent(thumbs.value, reactor), recent(thumbs.value, account)
        ], topPeers: [])
        XCTAssertEqual(ChatReactionAvatarVisibility.candidates(for: message(room, reaction: reactions), accountPeerId: account), [reactor])
        XCTAssertTrue(ChatReactionAvatarVisibility.candidates(for: message(reactor, reaction: reactions), accountPeerId: account).isEmpty)
        XCTAssertTrue(ChatReactionAvatarVisibility.candidates(for: message(account, reaction: reactions), accountPeerId: account).isEmpty)
        XCTAssertTrue(ChatReactionAvatarVisibility.candidates(for: message(channelId, reaction: reactions), accountPeerId: account).isEmpty)

        let group = channel(.group(.init(flags: [])))
        let broadcast = channel(.broadcast(.init(flags: [])))
        XCTAssertEqual(ChatReactionAvatarVisibility.candidates(for: message(channelId, channel: group, reaction: reactions), accountPeerId: account), [reactor])
        XCTAssertTrue(ChatReactionAvatarVisibility.candidates(for: message(channelId, channel: broadcast, reaction: reactions), accountPeerId: account).isEmpty)
    }

    private func user(_ id: PeerId) -> TelegramUser {
        TelegramUser(id: id, accessHash: nil, firstName: "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channel(_ info: TelegramChannelInfo) -> TelegramChannel {
        TelegramChannel(id: channelId, accessHash: nil, title: "Chat", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: info, flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func recent(_ reaction: MessageReaction.Reaction, _ id: PeerId) -> ReactionsMessageAttribute.RecentPeer {
        .init(value: reaction, isLarge: false, isUnseen: false, isMy: id == account, peerId: id, timestamp: nil)
    }

    private func message(_ id: PeerId, channel: TelegramChannel? = nil, reaction: ReactionsMessageAttribute) -> Message {
        var peers: [PeerId: Peer] = [reactor: user(reactor), account: user(account)]
        if let channel {
            peers[channel.id] = channel
        }
        return Message(stableId: 1, stableVersion: 1, id: .init(peerId: id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: user(account), text: "Message", attributes: [reaction], media: [], peers: SimpleDictionary(peers), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }
}
