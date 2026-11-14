import Postbox

struct SearchSenderPreviewVisibility {
    private let candidates: [MessageId: Set<PeerId>]

    init(messages: [Message], accountPeerId: PeerId) {
        var candidates: [MessageId: Set<PeerId>] = [:]
        for message in messages {
            let senders = ChatListSenderPreviewVisibility.candidates(
                chatPeerId: message.id.peerId,
                messages: [message],
                accountPeerId: accountPeerId
            )
            if !senders.isEmpty {
                candidates[message.id, default: []].formUnion(senders)
            }
        }
        self.candidates = candidates
    }

    func participatingSenders(revealed: Set<PeerId>) -> Set<PeerId> {
        return candidates.reduce(into: Set<PeerId>()) { senders, candidate in
            if !revealed.contains(candidate.key.peerId) {
                senders.formUnion(candidate.value)
            }
        }
    }

    func hidesPreview(_ id: MessageId, revealed: Set<PeerId>, hidden: Set<PeerId>) -> Bool {
        guard let senders = candidates[id] else { return false }
        return ChatListSenderPreviewVisibility.hidesPreview(
            chatPeerId: id.peerId,
            candidates: senders,
            revealed: revealed,
            hidden: hidden
        )
    }
}
