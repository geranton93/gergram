import ChatModeTypes
import MessageUtils
import Postbox
import TelegramContext
import TelegramCore
import TelegramTheme
import TelegramUtils

enum ChatReadUntilPolicy {
    static func peer(in presentation: ChatPresentationInterfaceState, accountPeerId: PeerId) -> Peer? {
        guard !presentation.isNotAccessible, presentation.selectionState == nil, presentation.reportMode == nil,
              !presentation.searchMode.inSearch, presentation.searchMode.tag == nil,
              let peer = presentation.peer, peer.id == presentation.chatLocation.peerId,
              peer.id != accountPeerId, !peer.isDeleted,
              supports(presentation.cachedData),
              peer.restrictionText(presentation.contentSettings) == nil else { return nil }
        switch (presentation.chatMode, presentation.chatLocation) {
        case (.history, .peer):
            return supports(peer, accountPeerId: accountPeerId) ? peer : nil
        case (.history, .thread), (.thread(.topic), .thread):
            guard topic(in: presentation) != nil, let channel = peer as? TelegramChannel, case .group = channel.info,
                  channel.flags.contains(.isForum), !channel.flags.contains(.isMonoforum), channel.participationStatus == .member else { return nil }
            return peer
        default:
            return nil
        }
    }

    static func topic(in presentation: ChatPresentationInterfaceState) -> Int64? {
        guard case let .thread(data) = presentation.chatLocation, data.isForumPost, !data.isMonoforumPost,
              !data.isNotAvailable, data.threadId > 1, data.threadId < Int64(Int32.max),
              data.threadId != Message.newTopicThreadId else { return nil }
        return data.threadId
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
        let threadId = topic(in: presentation)
        guard let peer = peer(in: presentation, accountPeerId: accountPeerId),
              isEligible(message, peerId: peer.id, accountPeerId: accountPeerId, threadId: threadId) else { return nil }
        guard let groupingKey = message.groupingKey else { return message }
        guard let album, album.contains(where: { $0.id == message.id }),
              album.allSatisfy({ $0.groupingKey == groupingKey && $0.id.peerId == peer.id && $0.id.namespace == Namespaces.Message.Cloud && $0.threadId == threadId }),
              let latest = album.max(by: { $0.id.id < $1.id.id }),
              isEligible(latest, peerId: peer.id, accountPeerId: accountPeerId, threadId: threadId) else { return nil }
        return latest
    }

    static func isEligible(_ message: Message, peerId: PeerId, accountPeerId: PeerId, threadId: Int64? = nil) -> Bool {
        message.id.peerId == peerId && message.id.namespace == Namespaces.Message.Cloud && message.id.id > 0 && message.id.id < Int32.max
            && message.threadId == threadId && threadId.map { Int64(message.id.id) > $0 } != false && message.effectivelyIncoming(accountPeerId)
            && !message.flags.contains(.Unsent) && !message.flags.contains(.Sending) && !message.flags.contains(.Failed)
            && !message.isScheduledMessage && message.adAttribute == nil && !(message.extendedMedia is TelegramMediaAction)
            && !message.containsSecretMedia && message.autoclearTimeout == nil && message.autoremoveAttribute == nil
            && message.activeEphemeralReplacementMessage == nil && !message.attributes.contains { $0 is EphemeralMessageAttribute }
    }
}
