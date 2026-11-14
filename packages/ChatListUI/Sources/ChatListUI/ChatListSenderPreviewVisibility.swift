import MessageUtils
import Postbox
import TelegramCore

enum ChatListSenderPreviewVisibility {
    struct Row: Hashable {
        let id: EngineChatList.Item.Id
        let peerId: PeerId
    }

    typealias CandidateRows = [Row: Set<PeerId>]

    static func isEligible(_ chatPeerId: PeerId) -> Bool {
        return chatPeerId.namespace == Namespaces.Peer.CloudGroup || chatPeerId.namespace == Namespaces.Peer.CloudChannel
    }

    static func candidates(chatPeerId: PeerId, messages: [Message], accountPeerId: PeerId) -> Set<PeerId> {
        guard isEligible(chatPeerId) else { return [] }
        return messages.reduce(into: Set<PeerId>()) { ids, message in
            ids.formUnion(MessageSenderVisibility.candidates(for: message, accountPeerId: accountPeerId))
        }
    }

    static func hidesPreview(chatPeerId: PeerId, candidates: Set<PeerId>, revealed: Set<PeerId>, hidden: Set<PeerId>) -> Bool {
        return !revealed.contains(chatPeerId) && !candidates.isDisjoint(with: hidden)
    }

    static func participatingSenders(in candidates: CandidateRows, revealed: Set<PeerId>) -> Set<PeerId> {
        return candidates.reduce(into: Set<PeerId>()) { ids, candidate in
            if !revealed.contains(candidate.key.peerId) {
                ids.formUnion(candidate.value)
            }
        }
    }

    static func previewMessage(_ messages: [Message], hidden: Bool) -> Message? {
        guard !hidden else { return nil }
        return messages.first(where: { !$0.text.isEmpty }) ?? messages.first
    }
}
