import InAppSettings
import LocalAnimations
import Postbox
import SwiftSignalKit
import TelegramCore
import TGUIKit

enum ChatLocalShadowBanAction {
    static func menuItem(for message: Message, shadowBannedSenderIds: Set<PeerId>, interaction: ChatInteraction) -> ContextMenuItem? {
        let context = interaction.context
        guard interaction.canManageLocalMessageVisibility,
              message.id.peerId == interaction.peerId,
              message.id.namespace == Namespaces.Message.Cloud,
              let sender = message.author,
              canHideSenderLocally(sender, accountPeerId: context.peerId),
              ChatBlockedSenderVisibility.candidates(for: message, accountPeerId: context.peerId).contains(sender.id) else {
            return nil
        }

        let senderId = sender.id
        let location = interaction.chatLocation
        let hidden = shadowBannedSenderIds.contains(senderId)
        return ContextMenuItem(localizedString(hidden ? "Gergram.Chat.RestoreSenderLocally" : "Gergram.Chat.HideSenderLocally"), handler: { [weak interaction] in
            guard let interaction, interaction.chatLocation == location, interaction.canManageLocalMessageVisibility else { return }
            _ = setLocalShadowBan(context.account.postbox, senderId: senderId, accountPeerId: context.peerId, hidden: !hidden).startStandalone()
        }, itemImage: (hidden ? MenuAnimation.menu_show : MenuAnimation.menu_hide).value)
    }
}
