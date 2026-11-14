import Dispatch
import Postbox
import SwiftSignalKit
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatParticipantVisibilityTests: XCTestCase {
    private let selfId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let firstId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let nextId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(3))
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(2))

    private struct Page: Equatable {
        let peers: [PeerId]
        let totalCount: Int
        let canLoadMore: Bool
    }

    func testScopePreservesDirectAndSavedChats() {
        let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(19))
        XCTAssertTrue(ChatParticipantVisibility.isEligible(chatPeerId: group, accountPeerId: selfId))
        XCTAssertTrue(ChatParticipantVisibility.isEligible(chatPeerId: channel, accountPeerId: selfId))
        XCTAssertFalse(ChatParticipantVisibility.isEligible(chatPeerId: firstId, accountPeerId: selfId))
        XCTAssertFalse(ChatParticipantVisibility.isEligible(chatPeerId: selfId, accountPeerId: selfId))
    }

    func testHiddenFirstPageKeepsRawTotalAndPaginationThenRestoresNameOnUnblock() {
        let page = Page(peers: [firstId], totalCount: 77, canLoadMore: true)
        let blocked = ValuePromise<Set<PeerId>>()
        var presented: [(Page, Set<PeerId>)] = []
        let disposable = ChatParticipantVisibility.project(
            .single(page),
            accountPeerId: selfId,
            participants: { Set($0.peers) },
            hideBlocked: .single(true),
            locallyHidden: .single([]),
            observeBlocked: { _ in blocked.get() }
        ).start(next: { presented.append($0) })
        defer { disposable.dispose() }

        XCTAssertEqual(presented.last?.0, page)
        XCTAssertEqual(presented.last?.1, [firstId])
        XCTAssertTrue(ChatParticipantVisibility.showsPagination(canLoadMore: page.canLoadMore, hasHiddenParticipants: !presented[0].1.isEmpty))
        blocked.set([firstId])
        XCTAssertTrue(presented.allSatisfy { $0.1 == [firstId] })
        blocked.set([])
        XCTAssertEqual(presented.last?.0.totalCount, 77)
        XCTAssertEqual(presented.last?.1, [])
        XCTAssertFalse(ChatParticipantVisibility.showsPagination(canLoadMore: false, hasHiddenParticipants: true))
    }

    func testLocalRulesAreIndependentAndDoNotRequeryUnchangedParticipants() {
        let page = Page(peers: [firstId, channel, firstId, selfId], totalCount: 120, canLoadMore: true)
        let pages = Promise<Page>(page)
        let hidden = ValuePromise<Set<PeerId>>([channel, selfId], ignoreRepeated: true)
        let hidesBlocked = ValuePromise(true, ignoreRepeated: true)
        var sourceStarts = 0
        var statusStarts = 0
        var statusDisposals = 0
        var latest: (Page, Set<PeerId>)?
        let disposable = ChatParticipantVisibility.project(
            pages.get() |> beforeNext { _ in sourceStarts += 1 },
            accountPeerId: selfId,
            participants: { Set($0.peers) },
            hideBlocked: hidesBlocked.get(),
            locallyHidden: hidden.get(),
            observeBlocked: { ids in
                XCTAssertEqual(ids, [self.firstId])
                statusStarts += 1
                return ValuePromise<Set<PeerId>>([self.firstId, self.selfId]).get() |> afterDisposed { statusDisposals += 1 }
            }
        ).start(next: { latest = $0 })
        defer { disposable.dispose() }

        XCTAssertEqual(sourceStarts, 1)
        XCTAssertEqual(statusStarts, 1)
        XCTAssertEqual(latest?.1, [firstId, channel])
        hidden.set([firstId])
        XCTAssertEqual(latest?.1, [firstId])
        pages.set(.single(Page(peers: [channel, firstId, selfId], totalCount: 121, canLoadMore: true)))
        XCTAssertEqual(sourceStarts, 2)
        XCTAssertEqual(statusStarts, 1)
        XCTAssertEqual(latest?.0.totalCount, 121)
        hidesBlocked.set(false)
        XCTAssertEqual(statusDisposals, 1)
        XCTAssertEqual(latest?.1, [firstId])
        hidden.set([])
        XCTAssertEqual(latest?.1, [])
        hidesBlocked.set(true)
        XCTAssertEqual(statusStarts, 2)
        disposable.dispose()
        XCTAssertEqual(statusDisposals, 2)
    }

    func testMembershipChangesKeepKnownOverlapAndIgnoreDiscardedQueuedStatus() {
        let initial = Page(peers: [firstId], totalCount: 22, canLoadMore: true)
        let next = Page(peers: [nextId, firstId], totalCount: 22, canLoadMore: false)
        let pages = Promise<Page>(initial)
        let firstBlocked = ValuePromise<Set<PeerId>>([firstId])
        let nextBlocked = ValuePromise<Set<PeerId>>()
        var latest: (Page, Set<PeerId>)?
        let disposable = ChatParticipantVisibility.project(
            pages.get(),
            accountPeerId: selfId,
            participants: { Set($0.peers) },
            hideBlocked: .single(true),
            locallyHidden: .single([]),
            observeBlocked: { ids in ids.count == 1 ? firstBlocked.get() : nextBlocked.get() }
        ).start(next: { latest = $0 })
        defer { disposable.dispose() }

        XCTAssertEqual(latest?.1, [firstId])
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            firstBlocked.set([])
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        pages.set(.single(next))
        XCTAssertEqual(latest?.1, [firstId, nextId])

        let drained = expectation(description: "Previous membership's status reached the main queue")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(latest?.1, [firstId, nextId])
        nextBlocked.set([firstId])
        XCTAssertEqual(latest?.0, next)
        XCTAssertEqual(latest?.1, [firstId])
    }

    func testRepeatedFullPageBatchesKeepNamespacedIdentityAndEveryParticipant() {
        let ids = (10 ... 275).map {
            PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(Int64($0)))
        }
        let page = Page(peers: ids + [channel, selfId, ids[0]], totalCount: 999, canLoadMore: true)
        var requested: [[PeerId]] = []
        var latest: (Page, Set<PeerId>)?
        let disposable = ChatParticipantVisibility.project(
            .single(page),
            accountPeerId: selfId,
            participants: { Set($0.peers) },
            hideBlocked: .single(true),
            locallyHidden: .single([channel]),
            observeBlocked: { batch in
                requested.append(batch)
                return .single(Set(batch))
            }
        ).start(next: { latest = $0 })
        defer { disposable.dispose() }

        XCTAssertEqual(requested.map(\.count), [128, 128, 10])
        XCTAssertEqual(requested.flatMap { $0 }, ids)
        XCTAssertEqual(latest?.1, Set(ids + [channel]))
    }

    private func user(_ id: PeerId, name: String) -> TelegramUser {
        TelegramUser(id: id, accessHash: nil, firstName: name, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    func testReadMenuProjectionFiltersBothSourcesWithoutLosingTimestampsOrCursor() {
        let blocked = user(firstId, name: "Hidden")
        let visible = user(nextId, name: "Visible")
        let account = user(selfId, name: "Self")
        let items = [
            EngineMessageReactionListContext.Item(peer: .init(blocked), reaction: .builtin("👍"), timestamp: 5, timestampIsReaction: true),
            EngineMessageReactionListContext.Item(peer: .init(visible), reaction: .builtin("👍"), timestamp: nil, timestampIsReaction: false)
        ]
        let reactions = EngineMessageReactionListContext.State(hasOutgoingReaction: false, totalCount: 120, items: items, canLoadMore: true)
        let state = MessageReadMenuRowItem.State.stats(read: [blocked, visible, account], readTimestamps: [visible.id: 7, account.id: 9], reactions: reactions, customFiles: nil)
        XCTAssertEqual(state.participantIds, [firstId, nextId, selfId])
        let rows = state.peers(excluding: [firstId])
        XCTAssertEqual(rows.map { $0.0.id }, [nextId, selfId])
        XCTAssertEqual(rows.map { $0.2 }, [7, 9])
        XCTAssertTrue(state.showsPagination(excluding: [firstId]))
        XCTAssertEqual(reactions.totalCount, 120)
        XCTAssertTrue(reactions.canLoadMore)
        XCTAssertEqual(state.peers.map { $0.0.id }, [firstId, nextId, selfId])
    }
}
