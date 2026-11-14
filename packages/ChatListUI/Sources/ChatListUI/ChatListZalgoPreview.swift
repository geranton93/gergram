import Foundation
import MessageTextUtils
import MessageUtils
import Postbox
import TelegramCore
import TelegramMediaUtils
import TelegramUtils
import TGUIKit

enum ChatListZalgoPreview {
    static func trimmedArchivePreview(_ source: NSAttributedString, bodyOffset: Int?) -> (text: NSAttributedString, bodyOffset: Int?) {
        guard let bodyOffset, bodyOffset >= 0, bodyOffset < source.length else { return (source.trimmed, nil) }
        guard bodyOffset != 0 else { return (source.trimmed, 0) }

        let bodyAttribute = NSAttributedString.Key("Gergram.ChatList.ArchivePreviewBody")
        let marked = NSMutableAttributedString(attributedString: source)
        marked.addAttribute(bodyAttribute, value: true, range: NSRange(location: bodyOffset, length: source.length - bodyOffset))
        let trimmed = NSMutableAttributedString(attributedString: marked.trimmed)
        let range = NSRange(location: 0, length: trimmed.length)
        var trimmedBodyOffset: Int?
        trimmed.enumerateAttribute(bodyAttribute, in: range) { value, range, stop in
            if value != nil {
                trimmedBodyOffset = range.location
                stop.pointee = true
            }
        }
        trimmed.removeAttribute(bodyAttribute, range: range)
        return (trimmed, trimmedBodyOffset)
    }

    static func isEligible(_ message: Message?) -> Bool {
        guard let message, !message.text.isEmpty, message.adAttribute == nil,
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
              }) else { return false }
        return true
    }

    static func transform(enabled: Bool, message: Message?, hasDraft: Bool, prefixLength: Int = 0) -> ((NSAttributedString) -> NSAttributedString?)? {
        guard enabled, !hasDraft, isEligible(message) else { return nil }
        return { source in
            guard source.length > prefixLength else { return nil }
            return ChatZalgoTextFilter.presentation(for: source, in: NSRange(location: prefixLength, length: source.length - prefixLength))
        }
    }
}
