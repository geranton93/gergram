import InAppSettings
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramCore

enum ChatParticipantVisibility {
    private static let blockedStatusBatchSize = 128

    static func isEligible(chatPeerId: PeerId, accountPeerId: PeerId) -> Bool {
        return chatPeerId != accountPeerId && (
            chatPeerId.namespace == Namespaces.Peer.CloudGroup ||
            chatPeerId.namespace == Namespaces.Peer.CloudChannel
        )
    }

    static func observe<Value>(
        _ values: Signal<Value, NoError>,
        chatPeerId: PeerId,
        context: any AccountContextProtocol,
        participants: @escaping (Value) -> Set<PeerId>
    ) -> Signal<(Value, Set<PeerId>), NoError> {
        let engine = context.engine
        let accountPeerId = context.peerId
        guard isEligible(chatPeerId: chatPeerId, accountPeerId: accountPeerId) else {
            return values |> deliverOnMainQueue |> map { ($0, []) }
        }
        return project(
            values,
            accountPeerId: accountPeerId,
            participants: participants,
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

    static func project<Value>(
        _ values: Signal<Value, NoError>,
        accountPeerId: PeerId,
        participants: @escaping (Value) -> Set<PeerId>,
        hideBlocked: Signal<Bool, NoError>,
        locallyHidden: Signal<Set<PeerId>, NoError>,
        observeBlocked: @escaping ([PeerId]) -> Signal<Set<PeerId>, NoError>
    ) -> Signal<(Value, Set<PeerId>), NoError> {
        let initialStatus = BlockedStatus(ids: [], knownBlocked: [])
        return Signal { subscriber in
            let snapshots = Promise<(Value, Set<PeerId>)>(initializeOnFirstAccess: values |> deliverOnMainQueue |> map { value in
                (value, participants(value).subtracting([accountPeerId]))
            })
            let blocked = combineLatest(queue: .mainQueue(), snapshots.get(), hideBlocked)
            |> map { snapshot, hidesBlocked in
                hidesBlocked ? Set(snapshot.1.filter { $0.namespace == Namespaces.Peer.CloudUser }) : []
            }
            |> distinctUntilChanged
            |> mapToSignal { ids -> Signal<BlockedStatus, NoError> in
                guard !ids.isEmpty else { return .single(initialStatus) }
                let ordered = ids.sorted()
                let batches = stride(from: 0, to: ordered.count, by: blockedStatusBatchSize).map { start in
                    observeBlocked(Array(ordered[start ..< min(start + blockedStatusBatchSize, ordered.count)]))
                }
                let status = combineLatest(queue: .mainQueue(), batches) |> map { batches in
                    BlockedStatus(ids: ids, knownBlocked: batches.reduce(into: Set<PeerId>()) { $0.formUnion($1) }.intersection(ids))
                }
                return status
            }

            let presentation = combineLatest(queue: .mainQueue(), snapshots.get(), hideBlocked, locallyHidden) |> map(Optional.init)
            return combineLatest(queue: .mainQueue(), blocked, initialStatus, presentation, nil)
            .start(next: { blocked, presentation in
                guard let ((value, ids), hidesBlocked, locallyHidden) = presentation else { return }
                var hidden = locallyHidden.intersection(ids)
                if hidesBlocked {
                    hidden.formUnion(blocked.knownBlocked.intersection(ids))
                    hidden.formUnion(ids.filter { $0.namespace == Namespaces.Peer.CloudUser && !blocked.ids.contains($0) })
                }
                subscriber.putNext((value, hidden))
            })
        }
    }

    static func showsPagination(canLoadMore: Bool, hasHiddenParticipants: Bool) -> Bool {
        return canLoadMore && hasHiddenParticipants
    }

    static func paginationItem(title: String, loadMore: @escaping () -> Void) -> ContextMenuItem {
        let item = ContextMenuItem(title, handler: loadMore)
        item.closesMenuOnAction = false
        return item
    }

    private struct BlockedStatus {
        let ids: Set<PeerId>
        let knownBlocked: Set<PeerId>
    }
}
