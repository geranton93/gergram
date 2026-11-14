import Foundation
import XCTest

final class ForumReadThroughTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1))
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let topic: Int64 = 10

    private func id(_ number: Int32) -> MessageId {
        MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: number)
    }

    private func setup(target: Int32 = 13) -> Account {
        let account = Account(peerId: accountId)
        let peer = TelegramChannel(id: peerId, accessHash: nil, title: "Forum", username: nil, photo: [], creationDate: 0,
                                   version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [.isForum],
                                   restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil,
                                   usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
                                   profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil,
                                   subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
        let transaction = account.postbox.data
        transaction.peer = peer
        transaction.threads[topic] = .init(maxIncomingReadId: 10, maxKnownMessageId: 18, incomingUnreadCount: 4)
        transaction.threads[20] = .init(maxIncomingReadId: 20, maxKnownMessageId: 26, incomingUnreadCount: 5)
        for (number, thread, incoming): (Int32, Int64, Bool) in [(11, topic, true), (12, topic, false), (target, topic, true), (14, 20, true), (18, topic, true)] {
            transaction.messages[id(number)] = Message(stableId: 1, stableVersion: 0, id: id(number), globallyUniqueId: nil, groupingKey: nil,
                groupInfo: nil, threadId: thread, timestamp: 50 - number, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [],
                localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "Message", attributes: [], media: [], peers: .init(),
                associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        }
        return account
    }

    private func read(_ account: Account, through number: Int32, thread: Int64? = nil) -> Bool {
        _internal_applyReadThroughForumTopicInteractively(account: account, messageId: id(number), threadId: thread ?? topic,
                                                         groupingKey: nil, isEligible: { _, _, _ in true }).value
    }

    func testUsesExactRequestAndOnlyUpdatesSelectedTopicAfterAcknowledgment() {
        let account = setup()
        let transaction = account.postbox.data
        let sibling = transaction.threads[20]
        account.network.respond = {
            XCTAssertEqual(transaction.threads[self.topic]?.maxIncomingReadId, 10)
            return .success(.boolTrue)
        }
        XCTAssertTrue(read(account, through: 13))
        XCTAssertEqual(account.network.requests, [.init(peer: .init(id: peerId), msgId: 10, readMaxId: 13)])
        XCTAssertEqual(transaction.threads[topic], .init(maxIncomingReadId: 13, maxKnownMessageId: 18, incomingUnreadCount: 2))
        XCTAssertEqual(transaction.threads[20], sibling)
        XCTAssertEqual(account.stateManager.notifications, [id(13)])
        XCTAssertTrue(transaction.writes.isEmpty)
    }

    func testFailedServerRequestKeepsLocalState() {
        let account = setup()
        let transaction = account.postbox.data
        account.network.respond = { .failure(.unavailable) }
        XCTAssertFalse(read(account, through: 13))
        XCTAssertEqual(transaction.threads[topic]?.maxIncomingReadId, 10)
        XCTAssertTrue(account.stateManager.notifications.isEmpty)
        XCTAssertEqual(account.postbox.transactionCount, 1)
    }

    func testOfflineDeadlineKeepsLocalState() {
        let account = setup()
        useNetworkTimeout = true
        defer { useNetworkTimeout = false }
        XCTAssertFalse(read(account, through: 13))
        XCTAssertEqual(maximumNetworkWait, 30.0)
        XCTAssertEqual(account.postbox.data.threads[topic]?.maxIncomingReadId, 10)
        XCTAssertTrue(account.stateManager.notifications.isEmpty)
    }

    func testNewerServerUpdateCannotBeOverwrittenByOlderAcknowledgment() {
        let account = setup()
        let transaction = account.postbox.data
        let newer = MessageHistoryThreadData(maxIncomingReadId: 18, maxKnownMessageId: 18, incomingUnreadCount: 0)
        account.network.respond = {
            transaction.threads[self.topic] = newer
            return .success(.boolTrue)
        }
        XCTAssertTrue(read(account, through: 13))
        XCTAssertEqual(transaction.threads[topic], newer)
        XCTAssertTrue(account.stateManager.notifications.isEmpty)
    }

    func testRejectsWrongTopicAndHolesBeforeSending() {
        let account = setup()
        let transaction = account.postbox.data
        XCTAssertFalse(read(account, through: 13, thread: 20))
        XCTAssertFalse(read(account, through: 12))
        transaction.holes = [11...11]
        XCTAssertFalse(read(account, through: 13))
        XCTAssertTrue(account.network.requests.isEmpty)
        XCTAssertTrue(account.stateManager.notifications.isEmpty)
    }

    func testIgnoresHolesOutsideTheSelectedRangeAndRejectsReread() {
        let account = setup()
        account.postbox.data.holes = [2...10, 14...19, 21...22]
        XCTAssertTrue(read(account, through: 13))
        XCTAssertFalse(read(account, through: 13))
        XCTAssertEqual(account.network.requests.count, 1)
        XCTAssertEqual(account.stateManager.notifications, [id(13)])
    }

    func testRejectsFirstHoleStraddlingTheCursorOrStartingAtTheTarget() {
        for hole: ClosedRange<Int32> in [8...11, 13...16] {
            let account = setup()
            account.postbox.data.holes = [21...22, hole, 25...30]
            XCTAssertFalse(read(account, through: 13))
            XCTAssertTrue(account.network.requests.isEmpty)
            XCTAssertTrue(account.stateManager.notifications.isEmpty)
        }
    }

    func testReadRangeIsBoundedBeforeTheNetworkRequest() {
        let account = setup(target: 523)
        XCTAssertFalse(read(account, through: 523))
        XCTAssertTrue(account.network.requests.isEmpty)
        XCTAssertEqual(account.postbox.data.threads[topic]?.maxIncomingReadId, 10)
    }
}
