import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore

enum ChatListActivityVisibility {
    typealias Snapshot = [PeerActivitySpace: [(PeerId, PeerInputActivity)]]

    private static let blockedStatusBatchSize = 128

    static func observe(
        context: any AccountContextProtocol,
        activities: Signal<Snapshot, NoError>
    ) -> Signal<Snapshot, NoError> {
        let engine = context.engine
        return filter(
            activities: activities,
            accountPeerId: context.peerId,
            hideBlocked: BlockedSenderVisibilitySettings.observe(),
            locallyHidden: localShadowBannedSenderIds(context.account.postbox),
            observeBlocked: { ids in
                let items = ids.map { TelegramEngine.EngineData.Item.Peer.IsBlocked(id: $0) }
                return engine.data.subscribe(EngineDataMap(items)) |> map { states in
                    Set(states.compactMap { id, state in state.knownValue == true ? id : nil })
                }
            }
        )
    }

    static func filter(
        activities: Signal<Snapshot, NoError>,
        accountPeerId: PeerId,
        hideBlocked: Signal<Bool, NoError>,
        locallyHidden: Signal<Set<PeerId>, NoError>,
        observeBlocked: @escaping ([PeerId]) -> Signal<Set<PeerId>, NoError>
    ) -> Signal<Snapshot, NoError> {
        let signal = Signal<Snapshot, NoError> { subscriber in
            let subscriptions = DisposableSet()
            let blockedSubscription = MetaDisposable()
            subscriptions.add(blockedSubscription)
            var currentActivities: Snapshot = [:]
            var hiddenLocally: Set<PeerId> = []
            var observedIds: Set<PeerId> = []
            var pendingIds: Set<PeerId> = []
            var knownBlocked: Set<PeerId> = []
            var blockedGeneration = 0

            func publish() {
                subscriber.putNext(project(
                    currentActivities,
                    locallyHidden: hiddenLocally,
                    excludedByBlockStatus: knownBlocked.union(pendingIds),
                    accountPeerId: accountPeerId
                ))
            }

            let activityUpdates = activities |> distinctUntilChanged(isEqual: areEqual)
            subscriptions.add(combineLatest(queue: .mainQueue(), activityUpdates, hideBlocked, locallyHidden)
                .start(next: { activities, hidesBlocked, locallyHidden in
                    currentActivities = activities
                    hiddenLocally = locallyHidden
                    let ids = hidesBlocked ? candidates(in: activities, accountPeerId: accountPeerId) : []
                    if ids != observedIds {
                        blockedGeneration &+= 1
                        pendingIds.formUnion(ids.subtracting(observedIds))
                        pendingIds.formIntersection(ids)
                        observedIds = ids
                        knownBlocked.formIntersection(ids)
                        if ids.isEmpty {
                            blockedSubscription.set(nil)
                        } else {
                            let generation = blockedGeneration
                            let subscription = MetaDisposable()
                            blockedSubscription.set(subscription)
                            subscription.set(blockedStatuses(for: ids, observeBlocked: observeBlocked).start(next: { blocked in
                                guard generation == blockedGeneration else { return }
                                pendingIds = []
                                knownBlocked = blocked.intersection(ids)
                                publish()
                            }))
                        }
                    }
                    publish()
                }))
            return subscriptions
        }
        return signal |> distinctUntilChanged(isEqual: areEqual)
    }

    private static func candidates(in activities: Snapshot, accountPeerId: PeerId) -> Set<PeerId> {
        var ids: Set<PeerId> = []
        for (space, entries) in activities where isRoomActivity(space) {
            for (id, _) in entries where id.namespace == Namespaces.Peer.CloudUser && id != accountPeerId {
                ids.insert(id)
            }
        }
        return ids
    }

    private static func blockedStatuses(
        for ids: Set<PeerId>,
        observeBlocked: ([PeerId]) -> Signal<Set<PeerId>, NoError>
    ) -> Signal<Set<PeerId>, NoError> {
        let ordered = ids.sorted()
        let batches = stride(from: 0, to: ordered.count, by: blockedStatusBatchSize).map { start in
            observeBlocked(Array(ordered[start ..< min(start + blockedStatusBatchSize, ordered.count)]))
        }
        return combineLatest(queue: .mainQueue(), batches) |> map { blocked in
            blocked.reduce(into: Set<PeerId>()) { $0.formUnion($1) }
        }
    }

    private static func project(
        _ activities: Snapshot,
        locallyHidden: Set<PeerId>,
        excludedByBlockStatus: Set<PeerId>,
        accountPeerId: PeerId
    ) -> Snapshot {
        guard !locallyHidden.isEmpty || !excludedByBlockStatus.isEmpty else { return activities }
        var result = activities
        for (space, entries) in activities where isRoomActivity(space) {
            let visible = entries.filter { id, _ in
                id == accountPeerId || (!locallyHidden.contains(id) && !excludedByBlockStatus.contains(id))
            }
            if visible.count != entries.count {
                result[space] = visible.isEmpty ? nil : visible
            }
        }
        return result
    }

    private static func isRoomActivity(_ space: PeerActivitySpace) -> Bool {
        guard space.peerId.namespace == Namespaces.Peer.CloudGroup || space.peerId.namespace == Namespaces.Peer.CloudChannel else {
            return false
        }
        switch space.category {
        case .global, .thread:
            return true
        default:
            return false
        }
    }

    private static func areEqual(_ lhs: Snapshot, _ rhs: Snapshot) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.allSatisfy { space, entries in
            guard let other = rhs[space], entries.count == other.count else { return false }
            return zip(entries, other).allSatisfy { left, right in
                left.0 == right.0 && left.1 == right.1
            }
        }
    }
}
