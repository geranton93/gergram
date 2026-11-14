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
        return MessageSenderVisibility.candidates(for: message, accountPeerId: accountPeerId)
    }
}
