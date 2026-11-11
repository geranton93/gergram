import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

enum ChatLocalHiddenItem: Hashable {
    case message(MessageId)
    case album(peerId: PeerId, namespace: MessageId.Namespace, groupingKey: Int64)

    init(_ message: Message) {
        if let groupingKey = message.groupingKey {
            self = .album(peerId: message.id.peerId, namespace: message.id.namespace, groupingKey: groupingKey)
        } else {
            self = .message(message.id)
        }
    }
}

final class ChatLocalMessageVisibility {
    private struct PeerVisibility: Equatable {
        var hiddenItems: Set<ChatLocalHiddenItem> = []
        var showsBlockedSenders = false
    }

    private static var instances: [AccountRecordId: ChatLocalMessageVisibility] = [:]

    static func get(_ account: Account) -> ChatLocalMessageVisibility {
        assert(Thread.isMainThread)
        if let existing = instances[account.id], existing.account === account {
            return existing
        }
        instances = instances.filter { $0.value.account != nil }
        let visibility = ChatLocalMessageVisibility(account: account)
        instances[account.id] = visibility
        return visibility
    }

    private weak var account: Account?
    private var stateByPeer: [PeerId: PeerVisibility] = [:]
    private let snapshots = ValuePromise<[PeerId: PeerVisibility]>([:], ignoreRepeated: true)

    private init(account: Account) {
        self.account = account
    }

    func observe(peerId: PeerId) -> Signal<Set<ChatLocalHiddenItem>, NoError> {
        return snapshots.get()
        |> map { $0[peerId]?.hiddenItems ?? [] }
        |> distinctUntilChanged
    }

    func hasHiddenItems(peerId: PeerId) -> Bool {
        assert(Thread.isMainThread)
        return stateByPeer[peerId]?.hiddenItems.isEmpty == false
    }

    func isHidden(_ message: Message) -> Bool {
        assert(Thread.isMainThread)
        return stateByPeer[message.id.peerId]?.hiddenItems.contains(ChatLocalHiddenItem(message)) == true
    }

    func hide(_ message: Message) {
        update(peerId: message.id.peerId) {
            $0.hiddenItems.insert(ChatLocalHiddenItem(message))
        }
    }

    func restore(peerId: PeerId) {
        update(peerId: peerId) { $0.hiddenItems.removeAll() }
    }

    func observeShowsBlockedSenders(peerId: PeerId) -> Signal<Bool, NoError> {
        return snapshots.get()
        |> map { $0[peerId]?.showsBlockedSenders ?? false }
        |> distinctUntilChanged
    }

    func showsBlockedSenders(peerId: PeerId) -> Bool {
        assert(Thread.isMainThread)
        return stateByPeer[peerId]?.showsBlockedSenders ?? false
    }

    func setShowsBlockedSenders(_ value: Bool, peerId: PeerId) {
        update(peerId: peerId) { $0.showsBlockedSenders = value }
    }

    private func update(peerId: PeerId, _ change: (inout PeerVisibility) -> Void) {
        assert(Thread.isMainThread)
        let previous = stateByPeer[peerId] ?? PeerVisibility()
        var updated = previous
        change(&updated)
        guard updated != previous else { return }
        stateByPeer[peerId] = updated == PeerVisibility() ? nil : updated
        snapshots.set(stateByPeer)
    }

    static func project(
        entries: [MessageHistoryEntry],
        hiddenItems: Set<ChatLocalHiddenItem>,
        revealedMessageId: MessageId?,
        blockedSenderIds: Set<PeerId> = [],
        accountPeerId: PeerId
    ) -> (entries: [MessageHistoryEntry], hiddenItems: Set<ChatLocalHiddenItem>) {
        guard !hiddenItems.isEmpty || !blockedSenderIds.isEmpty else { return (entries, hiddenItems) }
        var hiddenItems = hiddenItems
        let revealedItem = revealedMessageId.flatMap { id in
            entries.first(where: { $0.message.id == id }).map { ChatLocalHiddenItem($0.message) }
        }
        if let revealedItem {
            hiddenItems.remove(revealedItem)
        }
        let visibleEntries = entries.filter { entry in
            let item = ChatLocalHiddenItem(entry.message)
            if item == revealedItem { return true }
            if hiddenItems.contains(item) { return false }
            return blockedSenderIds.isEmpty || ChatBlockedSenderVisibility
                .candidates(for: entry.message, accountPeerId: accountPeerId)
                .isDisjoint(with: blockedSenderIds)
        }
        return (visibleEntries, hiddenItems)
    }
}
