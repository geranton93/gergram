import Postbox
import SwiftSignalKit
import TelegramCore

public func canHideSenderLocally(_ peer: Peer, accountPeerId: PeerId) -> Bool {
    guard peer.id != accountPeerId else { return false }
    if peer is TelegramUser { return true }
    if let channel = peer as? TelegramChannel, case .broadcast = channel.info { return true }
    return false
}

public func localShadowBannedSenderIds(_ postbox: Postbox) -> Signal<Set<PeerId>, NoError> {
    let key = ApplicationSpecificPreferencesKeys.localShadowBannedSenders
    return postbox.preferencesView(keys: [key]) |> map { view in
        return view.values[key]?.get(LocalShadowBanRules.self)?.senderIds ?? []
    } |> distinctUntilChanged
}

public func setLocalShadowBan(_ postbox: Postbox, senderId: PeerId, accountPeerId: PeerId, hidden: Bool) -> Signal<Never, NoError> {
    let key = ApplicationSpecificPreferencesKeys.localShadowBannedSenders
    return postbox.transaction { transaction in
        if hidden {
            guard let peer = transaction.getPeer(senderId), canHideSenderLocally(peer, accountPeerId: accountPeerId) else { return }
        }
        transaction.updatePreferencesEntry(key: key) { entry in
            let previous = entry?.get(LocalShadowBanRules.self) ?? LocalShadowBanRules()
            var updated = previous
            updated.setHidden(hidden, senderId: senderId)
            guard updated != previous else { return entry }
            return updated.senderIds.isEmpty ? nil : PreferencesEntry(updated)
        }
    } |> ignoreValues
}
