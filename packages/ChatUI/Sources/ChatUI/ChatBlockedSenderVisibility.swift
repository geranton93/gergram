import MessageUtils
import Postbox
import TelegramCore

enum ChatBlockedSenderVisibility {
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
