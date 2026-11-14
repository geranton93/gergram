import ChatModeTypes
import LocalAnimations
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUtils
import TGUIKit

enum ChatSenderMessageSearchAction {
    static func menuItem(for message: Message, interaction: ChatInteraction) -> ContextMenuItem? {
        guard let authorId = eligibleSender(of: message, interaction: interaction)?.id else {
            return nil
        }

        let location = interaction.chatLocation
        let mode = interaction.mode
        let messageId = message.id
        return ContextMenuItem(localizedString("Gergram.Chat.MenuSettings.senderSearch"), handler: { [weak interaction] in
            guard let interaction, interaction.chatLocation == location, interaction.mode == mode else { return }
            _ = (interaction.getMessages([messageId], false) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak interaction] messages in
                guard let interaction, interaction.canAnimateUpdates(),
                      interaction.chatLocation == location, interaction.mode == mode,
                      let current = messages.first, current.id == messageId,
                      let author = eligibleSender(of: current, interaction: interaction), author.id == authorId else {
                    return
                }
                interaction.searchPeerMessages(author)
            })
        }, itemImage: MenuAnimation.menu_search.value)
    }

    private static func eligibleSender(of message: Message, interaction: ChatInteraction) -> Peer? {
        guard !interaction.isLogInteraction, !interaction.isGlobalSearchMessage, !interaction.interactionContext.isFrozen,
              interaction.presentation.reportMode == nil, interaction.presentation.state != .selecting,
              message.id.peerId == interaction.peerId, message.id.namespace == Namespaces.Message.Cloud, message.id.id > 0,
              let peer = interaction.peer, (peer.isGroup || peer.isSupergroup), !peer.isMonoForum else {
            return nil
        }
        switch interaction.mode {
        case .history, .thread:
            return message.author
        default:
            return nil
        }
    }
}
