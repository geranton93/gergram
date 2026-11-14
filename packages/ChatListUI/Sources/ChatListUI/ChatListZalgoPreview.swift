import Foundation
import MessageTextUtils
import MessageUtils
import Postbox
import TelegramCore
import TelegramMediaUtils
import TelegramUtils

enum ChatListZalgoPreview {
    static func transform(enabled: Bool, message: Message?, hasDraft: Bool, prefixLength: Int = 0) -> ((NSAttributedString) -> NSAttributedString?)? {
        guard enabled, !hasDraft, let message, !message.text.isEmpty, message.adAttribute == nil,
              message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              message.id.peerId != servicePeerId, message.id.peerId != verifyCodePeerId,
              !message.isMediaSpoilered, !message.containsSecretMedia, message.autoremoveAttribute == nil,
              !message.attributes.contains(where: { $0 is RichTextMessageAttribute || $0 is TypingDraftMessageAttribute }),
              message.textEntities?.entities.contains(where: { $0.type == .Spoiler }) != true,
              message.media.allSatisfy({ media in
                  if let file = media as? TelegramMediaFile {
                      return !file.probablySticker && !file.isInstantVideo && !file.isMusic
                  }
                  return media is TelegramMediaImage || media is TelegramMediaWebpage
              }) else { return nil }
        return { source in
            guard source.length > prefixLength else { return nil }
            return ChatZalgoTextFilter.presentation(for: source, in: NSRange(location: prefixLength, length: source.length - prefixLength))
        }
    }
}
