import Dispatch
import Postbox
import SwiftSignalKit
import TelegramCore
import XCTest
@testable import ChatListUI

final class ChatListActivityVisibilityTests: XCTestCase {
    private let account = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let alice = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let bob = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(3))
    private let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(17))
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(19))

    func testOnlyRoomActivitiesUseHiddenSendersAndKeepTheirOrder() {
        let room = PeerActivitySpace(peerId: group, category: .global)
        let topic = PeerActivitySpace(peerId: channel, category: .thread(5))
        let privateConversation = PeerActivitySpace(peerId: alice, category: .global)
        let voiceChat = PeerActivitySpace(peerId: group, category: .voiceChat)
        let input: ChatListActivityVisibility.Snapshot = [
            room: [(alice, .typingText), (bob, .recordingVoice), (account, .typingText)],
            topic: [(channel, .typingText)],
            privateConversation: [(alice, .typingText)],
            voiceChat: [(alice, .speakingInGroupCall(timestamp: 7))]
        ]
        var queries: [[PeerId]] = []
        var result: ChatListActivityVisibility.Snapshot = [:]
        let disposable = ChatListActivityVisibility.filter(
            activities: .single(input),
            accountPeerId: account,
            hideBlocked: .single(true),
            locallyHidden: .single([channel, account]),
            observeBlocked: { ids in
                queries.append(ids)
                return .single([self.alice, self.account])
            }
        ).start(next: { result = $0 })
        defer { disposable.dispose() }

        XCTAssertEqual(queries, [[alice, bob]])
        XCTAssertEqual(result[room]?.map { $0.0 }, [bob, account])
        XCTAssertEqual(result[room]?.map { $0.1 }, [.recordingVoice, .typingText])
        XCTAssertNil(result[topic])
        XCTAssertEqual(result[privateConversation]?.map { $0.0 }, [alice])
        XCTAssertEqual(result[voiceChat]?.map { $0.0 }, [alice])
    }

    func testBlockChangesLocalChangesExpiryAndDisposalUpdateLive() {
        let room = PeerActivitySpace(peerId: group, category: .global)
        let topic = PeerActivitySpace(peerId: channel, category: .thread(7))
        let actions = Promise<ChatListActivityVisibility.Snapshot>([room: [(alice, .typingText)]])
        let hideBlocked = ValuePromise(false, ignoreRepeated: true)
        let locallyHidden = ValuePromise<Set<PeerId>>([], ignoreRepeated: true)
        let blocked = ValuePromise<Set<PeerId>>([], ignoreRepeated: true)
        var queries: [[PeerId]] = []
        var unsubscribes = 0
        var published: [ChatListActivityVisibility.Snapshot] = []
        let disposable = ChatListActivityVisibility.filter(
            activities: actions.get(),
            accountPeerId: account,
            hideBlocked: hideBlocked.get(),
            locallyHidden: locallyHidden.get(),
            observeBlocked: { ids in
                queries.append(ids)
                return blocked.get() |> afterDisposed { unsubscribes += 1 }
            }
        ).start(next: { published.append($0) })
        defer { disposable.dispose() }

        XCTAssertTrue(queries.isEmpty)
        XCTAssertEqual(published.last?[room]?.map { $0.1 }, [.typingText])

        locallyHidden.set([alice])
        XCTAssertNil(published.last?[room])
        locallyHidden.set([])
        XCTAssertEqual(published.last?[room]?.map { $0.1 }, [.typingText])

        hideBlocked.set(true)
        XCTAssertEqual(queries, [[alice]])
        blocked.set([alice])
        XCTAssertNil(published.last?[room])
        actions.set(.single([topic: [(alice, .recordingVoice)]]))
        XCTAssertEqual(queries, [[alice]])
        XCTAssertNil(published.last?[topic])

        blocked.set([])
        XCTAssertEqual(published.last?[topic]?.map { $0.1 }, [.recordingVoice])
        locallyHidden.set([alice])
        XCTAssertNil(published.last?[topic])
        XCTAssertEqual(queries, [[alice]])
        locallyHidden.set([])
        XCTAssertEqual(published.last?[topic]?.map { $0.1 }, [.recordingVoice])

        actions.set(.single([:]))
        XCTAssertEqual(unsubscribes, 1)
        XCTAssertTrue(published.last?.isEmpty == true)
        let countAfterExpiry = published.count
        blocked.set([alice])
        XCTAssertEqual(published.count, countAfterExpiry)

        actions.set(.single([room: [(bob, .typingText)]]))
        XCTAssertEqual(queries, [[alice], [bob]])
        disposable.dispose()
        XCTAssertEqual(unsubscribes, 2)
        let countAfterDisposal = published.count
        blocked.set([bob])
        locallyHidden.set([bob])
        XCTAssertEqual(published.count, countAfterDisposal)
    }

    func testUnknownNewParticipantsRemainVisibleWithKnownBlockedOverlap() {
        let room = PeerActivitySpace(peerId: group, category: .global)
        let actions = Promise<ChatListActivityVisibility.Snapshot>([room: [(alice, .typingText)]])
        let first = ValuePromise<Set<PeerId>>([alice])
        let next = ValuePromise<Set<PeerId>>()
        var result: ChatListActivityVisibility.Snapshot = [:]
        var queries: [[PeerId]] = []
        let disposable = ChatListActivityVisibility.filter(
            activities: actions.get(),
            accountPeerId: account,
            hideBlocked: .single(true),
            locallyHidden: .single([]),
            observeBlocked: { ids in
                queries.append(ids)
                return ids.count == 1 ? first.get() : next.get()
            }
        ).start(next: { result = $0 })
        defer { disposable.dispose() }

        XCTAssertNil(result[room])
        actions.set(.single([room: [(bob, .typingText), (alice, .recordingVoice)]]))
        XCTAssertEqual(queries, [[alice], [alice, bob]])
        XCTAssertNil(result[room])
        first.set([])
        XCTAssertNil(result[room])
        next.set([alice])
        XCTAssertEqual(result[room]?.map { $0.0 }, [bob])
        next.set([])
        XCTAssertEqual(result[room]?.map { $0.0 }, [bob, alice])
    }

    func testNewBlockedParticipantDoesNotFlashAndPreferenceOffCancelsPendingStatus() {
        let room = PeerActivitySpace(peerId: group, category: .global)
        let actions = Promise<ChatListActivityVisibility.Snapshot>([room: [(alice, .typingText)]])
        let hideBlocked = ValuePromise(true, ignoreRepeated: true)
        let knownBlocked = ValuePromise<Set<PeerId>>()
        var queries: [[PeerId]] = []
        var visible: [[PeerId]] = []
        let disposable = ChatListActivityVisibility.filter(
            activities: actions.get(),
            accountPeerId: account,
            hideBlocked: hideBlocked.get(),
            locallyHidden: .single([]),
            observeBlocked: { ids in
                queries.append(ids)
                return knownBlocked.get()
            }
        ).start(next: { visible.append($0[room]?.map { $0.0 } ?? []) })
        defer { disposable.dispose() }

        XCTAssertEqual(visible, [[]])
        knownBlocked.set([alice])
        XCTAssertEqual(visible, [[]])
        hideBlocked.set(false)
        XCTAssertEqual(visible, [[], [alice]])
        hideBlocked.set(true)
        XCTAssertEqual(queries, [[alice], [alice]])
        XCTAssertEqual(visible, [[], [alice], []])
    }

    func testQueuedStatusForAnExpiredGenerationCannotChangeNewActivities() {
        let room = PeerActivitySpace(peerId: group, category: .global)
        let actions = Promise<ChatListActivityVisibility.Snapshot>([room: [(alice, .typingText)]])
        let first = ValuePromise<Set<PeerId>>([])
        let next = ValuePromise<Set<PeerId>>([alice])
        var subscriptions = 0
        var visible: [[PeerId]] = []
        let disposable = ChatListActivityVisibility.filter(
            activities: actions.get(),
            accountPeerId: account,
            hideBlocked: .single(true),
            locallyHidden: .single([]),
            observeBlocked: { _ in
                subscriptions += 1
                return subscriptions == 1 ? first.get() : next.get()
            }
        ).start(next: { visible.append($0[room]?.map { $0.0 } ?? []) })
        defer { disposable.dispose() }

        XCTAssertEqual(visible, [[alice]])
        let didEnqueue = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { [alice] in
            first.set([alice])
            didEnqueue.signal()
        }
        XCTAssertEqual(didEnqueue.wait(timeout: .now() + 2), .success)

        actions.set(.single([:]))
        actions.set(.single([room: [(alice, .recordingVoice)]]))
        XCTAssertEqual(subscriptions, 2)
        next.set([])
        XCTAssertEqual(visible, [[alice], [], [alice]])

        let queueDrained = expectation(description: "Initial status callback has reached the main queue")
        DispatchQueue.main.async { queueDrained.fulfill() }
        wait(for: [queueDrained], timeout: 2)
        XCTAssertEqual(visible, [[alice], [], [alice]])
    }

    func testActiveSenderIdsAreDeduplicatedAndBatchedWithoutDroppingPeers() {
        let rooms = (1 ... 23).map {
            PeerActivitySpace(peerId: channel, category: .thread(Int64($0)))
        }
        let participants = (10 ... 239).map {
            PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(Int64($0)))
        }
        var input: ChatListActivityVisibility.Snapshot = [:]
        for index in rooms.indices {
            input[rooms[index]] = participants[(index * 10) ..< (index * 10 + 10)].map { ($0, .typingText) }
        }
        let repeatedRoom = PeerActivitySpace(peerId: group, category: .global)
        input[repeatedRoom] = [(participants[0], .typingText)]
        var queries: [[PeerId]] = []
        var result: ChatListActivityVisibility.Snapshot = [:]
        let disposable = ChatListActivityVisibility.filter(
            activities: .single(input),
            accountPeerId: account,
            hideBlocked: .single(true),
            locallyHidden: .single([]),
            observeBlocked: { ids in
                queries.append(ids)
                return .single(Set(ids))
            }
        ).start(next: { result = $0 })
        defer { disposable.dispose() }

        XCTAssertEqual(queries.map(\.count), [128, 102])
        XCTAssertEqual(queries.flatMap { $0 }, participants)
        XCTAssertTrue(result.isEmpty)
    }
}
