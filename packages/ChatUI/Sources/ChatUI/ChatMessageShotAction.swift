import AppKit
import ChatModeTypes
import DateUtils
import LocalAnimations
import Localization
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramTheme
import TelegramUtils
import TGUIKit
import UniformTypeIdentifiers

enum ChatMessageShotAction {
    private enum Destination {
        case clipboard
        case file
    }

    static func menuItem(for message: Message, selection: Set<MessageId>, selectedMessages: [Message], cachedData: CachedPeerData?, interaction: ChatInteraction) -> ContextMenuItem? {
        guard let peer = message.peers[message.id.peerId], !peerIsRestricted(peer, cachedData: cachedData),
              supportsChat(interaction), selection.isEmpty || selection.contains(message.id) else {
            return nil
        }

        let messages = selection.count > 1 ? selectedMessages : [message]
        let ids = selection.isEmpty ? Set([message.id]) : selection
        guard ids.count <= MessageShotRenderer.maximumMessageCount,
              Set(messages.map(\.id)) == ids,
              messages.allSatisfy({ supportsMessage($0, interaction: interaction, cachedData: cachedData) }) else {
            return nil
        }

        let menu = ContextMenu()
        menu.addItem(ContextMenuItem(strings().contextCopy, handler: { [weak interaction] in
            guard let interaction else { return }
            export(ids: ids, selection: selection, interaction: interaction, destination: .clipboard)
        }, itemImage: MenuAnimation.menu_copy_media.value))
        menu.addItem(ContextMenuItem(localizedString("Gergram.Chat.MessageShotSave"), handler: { [weak interaction] in
            guard let interaction else { return }
            export(ids: ids, selection: selection, interaction: interaction, destination: .file)
        }, itemImage: MenuAnimation.menu_save_as.value))
        let item = ContextMenuItem(localizedString("Gergram.Chat.MessageShot"), handler: {}, itemImage: MenuAnimation.menu_copy_media.value)
        item.submenu = menu
        return item
    }

    private static func supportsChat(_ interaction: ChatInteraction) -> Bool {
        guard !interaction.isLogInteraction, !interaction.interactionContext.isFrozen,
              interaction.presentation.reportMode == nil else {
            return false
        }
        switch interaction.mode {
        case .history, .thread:
            return true
        default:
            return false
        }
    }

    private static func peerIsRestricted(_ peer: Peer, cachedData: CachedPeerData?) -> Bool {
        if peer is TelegramSecretChat || peer.isCopyProtectionEnabled {
            return true
        }
        if let data = cachedData as? CachedUserData {
            return data.flags.contains(.copyProtectionEnabled) || data.flags.contains(.myCopyProtectionEnabled)
        }
        return false
    }

    private static func supportsMessage(_ message: Message, interaction: ChatInteraction, cachedData: CachedPeerData?) -> Bool {
        guard message.id.peerId == interaction.peerId, message.id.namespace == Namespaces.Message.Cloud,
              !message.containsSecretMedia, !message.isCopyProtected(cachedData: cachedData),
              message.autoclearTimeout == nil, message.autoremoveAttribute == nil,
              message.activeEphemeralReplacementMessage == nil, !message.flags.contains(.Sending),
              canForwardMessage(message, chatInteraction: interaction),
              !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute || $0 is RichTextMessageAttribute }),
              message.textEntities?.entities.contains(where: { entity in
                  if case .Spoiler = entity.type { return true }
                  return false
              }) != true else {
            return false
        }

        return (!message.text.isEmpty || message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile })) && message.media.allSatisfy {
            $0 is TelegramMediaImage || $0 is TelegramMediaFile || $0 is TelegramMediaWebpage
        }
    }

    private static func export(ids: Set<MessageId>, selection: Set<MessageId>, interaction: ChatInteraction, destination: Destination) {
        guard supportsChat(interaction), (interaction.presentation.selectionState?.selectedIds ?? []) == selection else { return }

        let context = interaction.interactionContext
        let location = interaction.chatLocation
        let mode = interaction.mode
        let peerId = location.peerId
        let refreshRequired = peerId.namespace == Namespaces.Peer.CloudUser && peerId != context.peerId
        let refresh = refreshRequired ? context.engine.peers.fetchAndUpdateCachedPeerData(peerId: peerId) : .single(true)
        let load = refresh
        |> take(1)
        |> mapToSignal { fresh -> Signal<([Message], CachedPeerData?)?, NoError> in
            guard fresh else { return .single(nil) }
            return context.account.postbox.transaction { transaction in
                guard let peer = transaction.getPeer(peerId) else { return nil }
                let cachedData = transaction.getPeerCachedData(peerId: peerId)
                guard (!refreshRequired || cachedData is CachedUserData), !peerIsRestricted(peer, cachedData: cachedData) else {
                    return nil
                }
                return (ids.compactMap { transaction.getMessage($0) }, cachedData)
            }
        }
        |> deliverOnMainQueue

        _ = load.startStandalone(next: { [weak interaction] result in
            guard let interaction, interaction.canAnimateUpdates(), supportsChat(interaction),
                  interaction.chatLocation == location, interaction.mode == mode,
                  (interaction.presentation.selectionState?.selectedIds ?? []) == selection else {
                return
            }

            guard let (messages, cachedData) = result, Set(messages.map(\.id)) == ids,
                  messages.allSatisfy({ supportsMessage($0, interaction: interaction, cachedData: cachedData) }) else {
                showModalText(for: context.window, text: localizedString("Gergram.Chat.MessageShotUnavailable"))
                return
            }
            guard messages.reduce(0, { $0 + $1.text.utf16.count }) <= 16_000,
                  let png = MessageShotRenderer.png(rows: rows(for: messages, interaction: interaction), background: theme.colors.background) else {
                showModalText(for: context.window, text: localizedString("Gergram.Chat.MessageShotRenderFailed"))
                return
            }

            switch destination {
            case .clipboard:
                let item = NSPasteboardItem()
                guard item.setData(png, forType: .png) else { return }
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.writeObjects([item]) {
                    showModalText(for: context.window, text: strings().contextAlertCopied)
                }
            case .file:
                save(png, in: context.window)
            }
        })
    }

    private static func save(_ png: Data, in window: Window) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Message Shot.png"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png]
        } else {
            panel.allowedFileTypes = ["png"]
        }
        panel.beginSheetModal(for: window) { [weak window] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                if let window {
                    showModalText(for: window, text: localizedString("Gergram.Chat.MessageShotSaveFailed"))
                }
            }
        }
    }

    private static func rows(for messages: [Message], interaction: ChatInteraction) -> [MessageShotRenderer.Row] {
        let context = interaction.interactionContext
        let palette = theme
        return messages.sorted { $0.index < $1.index }.map { message in
            let incoming = message.isIncoming(context.account, true)
            let date = DateSelectorUtil.chatFullDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp) - context.timeDifference))
            let title = [message.effectiveAuthor?.displayTitle, date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
            let header = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: palette.chat.grayText(incoming, true)])

            let text = ChatMessageItem.applyMessageEntities(with: message.attributes, for: message.text, message: message, context: context, fontSize: palette.fontSize, openInfo: { _, _, _, _ in }, textColor: palette.chat.textColor(incoming, true), linkColor: palette.chat.linkColor(incoming, true), monospacedPre: palette.chat.monospacedPreColor(incoming, true), monospacedCode: palette.chat.monospacedCodeColor(incoming, true), isDark: palette.colors.isDark, bubbled: true, ignoreLinks: true)
            let body = NSMutableAttributedString(attributedString: text)
            for media in message.media {
                let label: String
                if media is TelegramMediaImage {
                    label = strings().chatListPhoto
                } else if let file = media as? TelegramMediaFile {
                    label = file.isVideo ? strings().chatListVideo : (file.isVoice ? strings().chatListVoice : localizedString("Gergram.Chat.MessageShotAttachment"))
                } else {
                    continue
                }
                body.append(NSAttributedString(string: (body.length == 0 ? "" : "\n") + "[\(label)]", attributes: [.font: NSFont.systemFont(ofSize: palette.fontSize), .foregroundColor: palette.chat.grayText(incoming, true)]))
            }
            return MessageShotRenderer.Row(header: header, body: body, background: palette.chat.backgroundColor(incoming, true))
        }
    }
}
