import MessageUtils
import Postbox
import TGUIKit
import TelegramCore

enum ChatReactionAvatarVisibility {
    static func eligibleReactionCounts(_ reactions: [MessageReaction]) -> Bool {
        return reactions.allSatisfy { $0.count > 0 } && reactions.reduce(0, { $0 + Int64($1.count) }) <= 3
    }

    static func resolvedPeers(
        for reaction: MessageReaction,
        recentPeers: [ReactionsMessageAttribute.RecentPeer],
        resolve: (PeerId) -> Peer?
    ) -> [Peer] {
        guard reaction.count > 0, reaction.count <= 3 else { return [] }
        var peers: [Peer] = []
        for recent in recentPeers where recent.value == reaction.value {
            guard let peer = resolve(recent.peerId) else { continue }
            guard peers.count < reaction.count else { return [] }
            peers.append(peer)
        }
        return peers.count == reaction.count ? peers : []
    }

    static func candidates(for message: Message, accountPeerId: PeerId) -> Set<PeerId> {
        let chatPeerId = message.id.peerId
        guard chatPeerId != accountPeerId, message.adAttribute == nil else { return [] }
        if chatPeerId.namespace == Namespaces.Peer.CloudChannel {
            guard let channel = message.peers[chatPeerId] as? TelegramChannel, case .group = channel.info else { return [] }
        } else if chatPeerId.namespace != Namespaces.Peer.CloudGroup {
            return []
        }
        guard let reactions = message.effectiveReactions(accountPeerId, isTags: false),
              eligibleReactionCounts(reactions.reactions) else { return [] }

        var result: Set<PeerId> = []
        for reaction in reactions.reactions where !reaction.value.isEmpty {
            result.formUnion(resolvedPeers(for: reaction, recentPeers: reactions.recentPeers, resolve: { message.peers[$0] }).map(\.id))
        }
        result.remove(accountPeerId)
        return result
    }

    static func visiblePeers(_ peers: [Peer], excluding hidden: Set<PeerId>) -> [Peer] {
        guard !hidden.isEmpty else { return peers }
        return peers.contains(where: { hidden.contains($0.id) }) ? [] : peers
    }

    static func countText(_ reaction: MessageReaction, hasAvatars: Bool) -> String? {
        return hasAvatars ? nil : Int(reaction.count).prettyNumber
    }
}
