import InAppSettings
import LocalAnimations
import Localization
import Postbox
import TelegramContext
import TelegramCore
import TGUIKit

extension StickerPackIdentifier {
    init?(packId: ItemCollectionId) {
        let kind: Kind
        switch packId.namespace {
        case Namespaces.ItemCollection.CloudStickerPacks:
            kind = .stickerSet
        case Namespaces.ItemCollection.CloudEmojiPacks:
            kind = .emojiSet
        default:
            return nil
        }
        self.init(kind: kind, id: packId.id)
    }

    init?(customEmoji file: TelegramMediaFile) {
        guard file.isCustomEmoji, file.fileId.namespace == Namespaces.Media.CloudFile else { return nil }
        self.init(kind: .emoji, id: file.fileId.id)
    }

    func copyMenuItem(context: any AccountContextProtocol, title: String? = nil) -> ContextMenuItem? {
        guard FastSettings.canViewPeerId else { return nil }
        let clipboardText = self.clipboardText
        return ContextMenuItem(title ?? localizedString(kind.rawValue), handler: {
            guard FastSettings.canViewPeerId else { return }
            copyToClipboard(clipboardText)
            showModalText(for: context.window, text: strings().contextAlertCopied)
        }, itemImage: MenuAnimation.menu_copy.value)
    }
}
