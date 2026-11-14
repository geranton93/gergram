import XCTest

final class ExactReadThroughTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let cloud = Namespaces.Message.Cloud
    private let local = Namespaces.Message.Local

    private func readState(_ cursor: Int32, known: Int32 = 20, count: Int32 = 4, marked: Bool = false) -> PeerReadState {
        .idBased(maxIncomingReadId: cursor, maxOutgoingReadId: 1, maxKnownId: known, count: count, markedUnread: marked)
    }

    private func id(_ value: Int32) -> MessageId {
        MessageId(peerId: peerId, namespace: cloud, id: value)
    }

    private func message(_ value: Int32, peer: Peer, album: Int64? = nil) -> Message {
        Message(stableId: 1, stableVersion: 0, id: id(value), globallyUniqueId: nil, groupingKey: album, groupInfo: nil,
                threadId: nil, timestamp: 1, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [],
                forwardInfo: nil, author: peer, text: "message", attributes: [], media: [], peers: .init(), associatedMessages: .init(),
                associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testStrictModePreservesUnreadAfterSelectedBoundaryWhenLocalTopIsOutgoing() {
        let table = MessageHistoryReadStateTable()
        table.states[peerId] = .init([cloud: readState(3), local: readState(1, count: 2)])
        let result = table.applyIncomingMaxReadId(id(7), incomingStatsInRange: { namespace, start, end in
            XCTAssertEqual(namespace, self.cloud)
            XCTAssertEqual(start, 4)
            XCTAssertEqual(end, 7)
            return (1, false)
        }, topMessageId: (12, true), interactive: true, exactBoundary: true)
        XCTAssertEqual(result.0?.states.first { $0.0 == cloud }?.1, readState(7, count: 3))
        XCTAssertEqual(result.0?.states.first { $0.0 == local }?.1, readState(1, count: 2))
    }

    func testStrictModeCannotRegressAMarkedUnreadOrNewerCursor() {
        let table = MessageHistoryReadStateTable()
        let original = readState(9, marked: true)
        table.states[peerId] = .init([cloud: original])
        let result = table.applyIncomingMaxReadId(id(7), incomingStatsInRange: { _, _, _ in
            XCTFail("A stale request must not read a range")
            return (0, false)
        }, topMessageId: (12, true), interactive: true, exactBoundary: true)
        XCTAssertNil(result.0)
        XCTAssertEqual(table.states[peerId]?.namespaces[cloud], original)
    }

    func testExactTopRequiresNoKnownNewerMessagesToClearAll() {
        let table = MessageHistoryReadStateTable()
        table.states[peerId] = .init([cloud: readState(3)])
        let incomplete = table.applyIncomingMaxReadId(id(7), incomingStatsInRange: { _, _, _ in (1, false) },
                                                     topMessageId: (7, false), interactive: true, exactBoundary: true)
        XCTAssertEqual(incomplete.0?.count, 3)
        let complete = table.applyIncomingMaxReadId(id(20), incomingStatsInRange: { _, _, _ in (1, true) },
                                                   topMessageId: (20, false), interactive: true, exactBoundary: true)
        XCTAssertEqual(complete.0?.count, 0)
        XCTAssertTrue(complete.1)
    }

    func testStrictModeNeverFallsBackToAnotherNamespace() {
        let table = MessageHistoryReadStateTable()
        table.states[peerId] = .init([local: readState(1, count: 2)])
        let result = table.applyInteractiveMaxReadIndex(postbox: .init(), messageIndex: .init(id: id(7), timestamp: 1),
            incomingStatsInRange: { _, _, _ in XCTFail(); return (0, false) },
            incomingIndexStatsInRange: { _, _ in XCTFail(); return (0, false, []) },
            topMessageId: nil, topMessageIndexByNamespace: { _ in XCTFail(); return nil }, exactBoundary: true)
        XCTAssertNil(result.0)
        XCTAssertEqual(result.1, .None)
    }

    func testTransactionRejectsAStaleDeletedOrRegroupedEndpointBeforeNotification() {
        let account = Account(peerId: accountId)
        let peer = TelegramUser(id: peerId, accessHash: nil, firstName: "Person", lastName: nil, username: nil, phone: nil,
                                photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [],
                                storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
                                profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        let transaction = account.postbox.data
        transaction.peer = peer
        transaction.readState = .init(states: [(cloud, readState(2))])
        func apply(_ grouping: Int64? = nil) -> Bool {
            _internal_applyReadThroughMessageInteractively(account: account, messageId: id(7), groupingKey: grouping,
                                                          isEligible: { _, _, _ in true }).value
        }
        XCTAssertFalse(apply())
        transaction.message = message(7, peer: peer, album: 10)
        XCTAssertFalse(apply())
        transaction.album = [message(7, peer: peer, album: 10), message(8, peer: peer, album: 10)]
        XCTAssertFalse(apply(10))
        transaction.album = [message(5, peer: peer, album: 10), message(7, peer: peer, album: 10)]
        transaction.readState = .init(states: [(cloud, readState(9, marked: true))])
        XCTAssertFalse(apply(10))
        transaction.readState = .init(states: [(cloud, readState(2)), (local, readState(1, count: 1))])
        XCTAssertFalse(apply(10))
        XCTAssertTrue(transaction.writes.isEmpty)
        XCTAssertTrue(account.stateManager.notifications.isEmpty)
        transaction.readState = .init(states: [(cloud, readState(2))])
        XCTAssertTrue(apply(10))
        XCTAssertEqual(account.postbox.transactionCount, 6)
        XCTAssertEqual(transaction.writes.map(\.id), [id(7)])
        XCTAssertEqual(account.stateManager.notifications, [id(7)])
    }
}
