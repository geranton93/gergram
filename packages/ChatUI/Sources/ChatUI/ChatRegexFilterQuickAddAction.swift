import AlertsUI
import Foundation
import InAppSettings
import LocalAnimations
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramCore
import TGUIKit

enum ChatRegexFilterQuickAddAction {
    static func selectedLiteral(message: Message, layout: TextViewLayout?) -> ChatLiteralMessageFilter? {
        guard let layout else { return nil }
        let source = layout.attributedString
        let range = layout.selectedRange.range
        guard range.location >= 0, range.location <= source.length, range.length > 0,
              range.length <= source.length - range.location,
              range.length <= LocalMessageFilterEvaluation.maximumPatternLength else { return nil }
        let text = (source.string as NSString).substring(with: range)
        return ChatLiteralMessageFilter(selectedText: text, originalText: message.text)
    }

    static func menuItem(message: Message, literal: ChatLiteralMessageFilter, cachedData: CachedPeerData?, interaction: ChatInteraction) -> ContextMenuItem? {
        let context = interaction.interactionContext
        let accountPeerId = context.peerId
        let id = message.id
        let location = interaction.chatLocation
        let mode = interaction.mode
        guard id.peerId == interaction.peerId, interaction.canManageLocalMessageVisibility,
              message.text.utf16.elementsEqual(literal.sourceText.utf16),
              let peer = message.peers[id.peerId] ?? interaction.peer,
              supportsMessage(message, peer: peer, cachedData: cachedData, accountPeerId: accountPeerId) else { return nil }

        let title = localizedString("Gergram.Chat.AddTextFilterFromMessage")
        let rule = LocalMessageFilterRule(pattern: literal.pattern, chatId: id.peerId, isCaseInsensitive: true)
        return ContextMenuItem(title, handler: { [weak interaction] in
            guard let interaction, interaction.canAnimateUpdates(), interaction.canManageLocalMessageVisibility,
                  interaction.chatLocation == location, interaction.mode == mode, interaction.presentation.state != .selecting else { return }

            let info = String(format: localizedString("Gergram.Chat.ConfirmLiteralFilter"), String(reflecting: literal.text))
            verifyAlert_button(for: context.window, header: title, information: info, ok: title, successHandler: { [weak interaction] _ in
                guard let interaction, interaction.canAnimateUpdates(), interaction.canManageLocalMessageVisibility,
                      interaction.chatLocation == location, interaction.mode == mode, interaction.presentation.state != .selecting else { return }

                let save = context.account.postbox.transaction { transaction -> Bool in
                    guard let current = transaction.getMessage(id), current.text.utf16.elementsEqual(literal.sourceText.utf16),
                          let peer = transaction.getPeer(id.peerId),
                          supportsMessage(current, peer: peer, cachedData: transaction.getPeerCachedData(peerId: id.peerId), accountPeerId: accountPeerId) else { return false }
                    return updateLocalMessageFilterPreferences(transaction) { preferences in
                        guard preferences.isEnabled else { return false }
                        if let duplicate = preferences.rules.first(where: { $0.chatId == rule.chatId && $0.isCaseInsensitive && !$0.isReversed && $0.pattern.utf16.elementsEqual(rule.pattern.utf16) }) {
                            var enabled = duplicate
                            enabled.isEnabled = true
                            return preferences.upsert(enabled)
                        }
                        return preferences.upsert(rule)
                    }
                }
                _ = (save |> deliverOnMainQueue).startStandalone(next: { [weak interaction] saved in
                    if !saved, let interaction, interaction.canAnimateUpdates(), interaction.chatLocation == location, interaction.mode == mode {
                        alert(for: context.window, info: localizedString("Gergram.Chat.FilterRuleSaveFailed"))
                    }
                })
            })
        }, itemImage: MenuAnimation.menu_show_info.value)
    }

    private static func supportsMessage(_ message: Message, peer: Peer, cachedData: CachedPeerData?, accountPeerId: PeerId) -> Bool {
        guard LocalMessageFilterPreferences.acceptsChat(message.id.peerId), message.id.namespace == Namespaces.Message.Cloud,
              message.effectivelyIncoming(accountPeerId), message.adAttribute == nil, message.paidContent == nil,
              !message.containsSecretMedia, !message.isCopyProtected(cachedData: cachedData), !peer.isCopyProtectionEnabled,
              message.autoclearTimeout == nil, message.autoremoveAttribute == nil, message.activeEphemeralReplacementMessage == nil,
              !message.media.contains(where: { $0 is TelegramMediaAction }),
              !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute || $0 is RichTextMessageAttribute }),
              message.textEntities?.entities.contains(where: { entity in
                  if case .Spoiler = entity.type { return true }
                  return false
              }) != true else { return false }
        if let data = cachedData as? CachedUserData {
            return !data.flags.contains(.copyProtectionEnabled) && !data.flags.contains(.myCopyProtectionEnabled)
        }
        return message.id.peerId.namespace != Namespaces.Peer.CloudUser
    }
}
