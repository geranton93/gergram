import ChatModeTypes
import MessageUtils
import Postbox
import TelegramContext
import TelegramCore
import TelegramTheme
import TelegramUtils

enum ChatReadUntilPolicy {
    static func peer(in presentation: ChatPresentationInterfaceState, accountPeerId: PeerId) -> Peer? {
        guard presentation.chatMode == .history, case let .peer(peerId) = presentation.chatLocation,
              !presentation.isNotAccessible, presentation.selectionState == nil, presentation.reportMode == nil,
              !presentation.searchMode.inSearch, presentation.searchMode.tag == nil,
              let peer = presentation.peer, peer.id == peerId, supports(peer, accountPeerId: accountPeerId),
              supports(presentation.cachedData),
              peer.restrictionText(presentation.contentSettings) == nil else { return nil }
        return peer
    }

    static func supports(_ peer: Peer, accountPeerId: PeerId) -> Bool {
        guard peer.id != accountPeerId, !peer.isDeleted, !peer.isForumOrMonoForum else { return false }
        switch peer {
        case let channel as TelegramChannel:
            return channel.participationStatus == .member
        case let group as TelegramGroup:
            return group.membership == .Member && group.migrationReference == nil
        default:
            return peer is TelegramUser
        }
    }

    static func supports(_ cachedData: CachedPeerData?) -> Bool {
        guard let channel = cachedData as? CachedChannelData else { return true }
        return !channel.isNotAccessible && channel.migrationReference == nil
    }

    static func target(message: Message, album: [Message]?, presentation: ChatPresentationInterfaceState, accountPeerId: PeerId) -> Message? {
        guard let peer = peer(in: presentation, accountPeerId: accountPeerId),
              isEligible(message, peerId: peer.id, accountPeerId: accountPeerId) else { return nil }
        guard let groupingKey = message.groupingKey else { return message }
        guard let album, album.contains(where: { $0.id == message.id }),
              album.allSatisfy({ $0.groupingKey == groupingKey && $0.id.peerId == peer.id && $0.id.namespace == Namespaces.Message.Cloud }),
              let latest = album.max(by: { $0.id.id < $1.id.id }),
              isEligible(latest, peerId: peer.id, accountPeerId: accountPeerId) else { return nil }
        return latest
    }

    static func isEligible(_ message: Message, peerId: PeerId, accountPeerId: PeerId) -> Bool {
        message.id.peerId == peerId && message.id.namespace == Namespaces.Message.Cloud && message.id.id > 0 && message.id.id < Int32.max
            && message.threadId == nil && message.effectivelyIncoming(accountPeerId)
            && !message.flags.contains(.Unsent) && !message.flags.contains(.Sending) && !message.flags.contains(.Failed)
            && !message.isScheduledMessage && message.adAttribute == nil && !(message.extendedMedia is TelegramMediaAction)
            && !message.containsSecretMedia && message.autoclearTimeout == nil && message.autoremoveAttribute == nil
            && message.activeEphemeralReplacementMessage == nil && !message.attributes.contains { $0 is EphemeralMessageAttribute }
    }
}
