import InAppSettings
import XCTest
import Postbox
import SwiftSignalKit
import TelegramCore
@testable import ChatUI

final class ChatLocalMessageVisibilityTests: XCTestCase {
    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))

    private func user(_ id: Int64) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, profileColor: nil, backgroundEmojiId: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func entry(
        _ id: Int32,
        peer: Int64 = 1,
        namespace: MessageId.Namespace = Namespaces.Message.Cloud,
        album: Int64? = nil,
        author: Peer? = nil,
        forwardedAuthor: Peer? = nil,
        inlineBot: PeerId? = nil,
        text: String = "Message",
        direct: Bool = false,
        incoming: Bool = true
    ) -> MessageHistoryEntry {
        let peerId = (direct ? author?.id : nil) ?? PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(peer))
        let forwardInfo = forwardedAuthor.map { sender in
            MessageForwardInfo(author: sender, source: nil, sourceMessageId: nil, date: id, authorSignature: nil, psaType: nil, flags: [])
        }
        let message = Message(
            stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: peerId, namespace: namespace, id: id),
            globallyUniqueId: nil, groupingKey: album, groupInfo: nil, threadId: nil, timestamp: id,
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo,
            author: author, text: text, attributes: inlineBot.map { [InlineBotMessageAttribute(peerId: $0, title: nil)] } ?? [], media: [], peers: SimpleDictionary(),
            associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:],
            associatedThreadInfo: nil, associatedStories: [:]
        )
        return MessageHistoryEntry(
            message: message, isRead: false, location: nil, monthLocation: nil,
            attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)
        )
    }

    func testHidingAnAlbumDoesNotHideOtherPeersOrNamespaces() {
        let first = entry(1, album: 100)
        let second = entry(2, album: 100)
        let otherPeer = entry(3, peer: 2, album: 100)
        let otherNamespace = entry(4, namespace: Namespaces.Message.Local, album: 100)
        let ordinary = entry(5)
        let hiddenItems: Set<ChatLocalHiddenItem> = [ChatLocalHiddenItem(first.message)]
        let original = [first, second, otherPeer, otherNamespace, ordinary]

        let projection = ChatLocalMessageVisibility.project(
            entries: original, hiddenItems: hiddenItems, revealedMessageId: nil, accountPeerId: accountPeerId
        )

        XCTAssertEqual(projection.entries.map { $0.message.id }, [otherPeer, otherNamespace, ordinary].map { $0.message.id })
        XCTAssertEqual(projection.hiddenItems, hiddenItems)
        XCTAssertEqual(original.count, 5)
    }

    func testExplicitFocusRevealsTargetWithoutClearingOtherHiddenItems() {
        let first = entry(1, album: 100)
        let second = entry(2, album: 100)
        let hidden = entry(3)
        let albumKey = ChatLocalHiddenItem(first.message)
        let hiddenKey = ChatLocalHiddenItem(hidden.message)
        let hiddenItems: Set<ChatLocalHiddenItem> = [albumKey, hiddenKey]

        let projection = ChatLocalMessageVisibility.project(
            entries: [first, second, hidden],
            hiddenItems: hiddenItems,
            revealedMessageId: second.message.id,
            accountPeerId: accountPeerId
        )

        XCTAssertEqual(projection.entries.map { $0.message.id }, [first.message.id, second.message.id])
        XCTAssertEqual(projection.hiddenItems, [hiddenKey])
        XCTAssertEqual(hiddenItems, [albumKey, hiddenKey])
    }

    func testBlockedSenderFilteringKeepsDirectDialogAndOutgoingMessages() {
        let blocked = user(101)
        let allowed = user(102)
        let account = user(100)
        let groupMessage = entry(1, author: blocked)
        let forwarded = entry(2, author: allowed, forwardedAuthor: blocked)
        let direct = entry(3, author: blocked, direct: true)
        let outgoing = entry(4, author: account, forwardedAuthor: blocked, incoming: false)
        let ordinary = entry(5, author: allowed)

        let projection = ChatLocalMessageVisibility.project(
            entries: [groupMessage, forwarded, direct, outgoing, ordinary],
            hiddenItems: [],
            revealedMessageId: nil,
            filteredSenderIds: [blocked.id],
            accountPeerId: accountPeerId
        )

        XCTAssertEqual(projection.entries.map { $0.message.id }, [direct, outgoing, ordinary].map { $0.message.id })
    }

    func testLocalShadowBanMatchesChannelAndInlineBotWhileAllowingExplicitReveal() {
        let channel = TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(101)), accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .broadcast(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
        let sameNumberUser = user(101)
        let botId = user(102).id
        let channelMessage = entry(1, author: channel)
        let forwarded = entry(2, author: sameNumberUser, forwardedAuthor: channel)
        let inline = entry(3, author: sameNumberUser, inlineBot: botId)
        let sameNumber = entry(4, author: sameNumberUser)
        let directChannel = entry(5, author: channel, direct: true)
        let original = [channelMessage, forwarded, inline, sameNumber, directChannel]

        let projection = ChatLocalMessageVisibility.project(
            entries: original, hiddenItems: [], revealedMessageId: forwarded.message.id,
            filteredSenderIds: [channel.id, botId], accountPeerId: accountPeerId
        )

        XCTAssertEqual(projection.entries.map { $0.message.id }, [forwarded, sameNumber, directChannel].map { $0.message.id })
        XCTAssertTrue(projection.hiddenItems.isEmpty)
    }

    func testRegexProjectionFiltersAlbumTextAndKeepsOutgoingMessagesVisible() {
        let sender = user(101)
        let account = user(100)
        let first = entry(1, album: 100, author: sender, text: "Ordinary text")
        let second = entry(2, album: 100, author: sender, text: "Example spam")
        let outgoing = entry(3, author: account, text: "Example spam", incoming: false)
        let manual = entry(4, author: sender, text: "Manually hidden")
        let entries = [first, second, outgoing, manual]
        let manualRules = Set([ChatLocalHiddenItem(manual.message)])
        let completed = expectation(description: "Regex history projection")
        let disposable = ChatRegexFilterProjection.hiddenItems(entries: entries, rules: [.init(pattern: "spam")], accountPeerId: accountPeerId).start(next: { regexItems in
            XCTAssertEqual(regexItems, [ChatLocalHiddenItem(first.message)])
            let result = ChatLocalMessageVisibility.project(entries: entries, hiddenItems: manualRules, revealedMessageId: second.message.id, regexHiddenItems: regexItems, accountPeerId: self.accountPeerId)
            XCTAssertEqual(result.entries.map { $0.message.id }, [first, second, outgoing].map { $0.message.id })
            XCTAssertEqual(result.hiddenItems, manualRules)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 2.0)
        disposable.dispose()
    }
}
