import MessageUtils
import Postbox
import TelegramCore

enum ChatBlockedSenderVisibility {
    struct Candidates {
        let messageSenders: Set<PeerId>
        let reactionAvatars: Set<PeerId>

        var peerIds: Set<PeerId> {
            messageSenders.union(reactionAvatars)
        }

        var blockedPeerIds: Set<PeerId> {
            messageSenders.union(reactionAvatars.filter { $0.namespace == Namespaces.Peer.CloudUser })
        }

        func project(knownBlocked: Set<PeerId>, locallyHidden: Set<PeerId>) -> Self {
            let hidden = knownBlocked.union(locallyHidden)
            return Self(
                messageSenders: messageSenders.intersection(hidden),
                reactionAvatars: reactionAvatars.intersection(hidden)
            )
        }

        static func shouldFilter(hidesBlocked: Bool, showsFilteredSenders: Bool, locallyHidden: Set<PeerId>) -> Bool {
            return !showsFilteredSenders && (hidesBlocked || !locallyHidden.isEmpty)
        }
    }

    static func candidates(for message: Message, accountPeerId: PeerId) -> Set<PeerId> {
        guard message.effectivelyIncoming(accountPeerId), message.adAttribute == nil else { return [] }
        var peerIds: Set<PeerId> = []
        if message.author?.id != message.id.peerId {
            if let authorId = message.author?.id {
                peerIds.insert(authorId)
            }
            if let originalAuthorId = message.forwardInfo?.author?.id {
                peerIds.insert(originalAuthorId)
            }
        }
        for attribute in message.attributes {
            if let bot = attribute as? InlineBotMessageAttribute, let peerId = bot.peerId {
                peerIds.insert(peerId)
            }
        }
        return peerIds
    }
}
