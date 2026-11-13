import AppKit
import ChatModeTypes
import ColorPalette
import DateUtils
import LocalAnimations
import Localization
import MessageUtils
import Postbox
import Strings
import SwiftSignalKit
import TelegramCore
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import TGUIKit
import UniformTypeIdentifiers

enum ChatMessageShotAction {
    private typealias Snapshot = (messages: [Message], cachedData: CachedPeerData?)
    private typealias PreparedShot = (snapshot: Snapshot, previews: [MessageId: Preview])

    private struct PreviewRequest {
        let id: MessageId
        let mediaIndex: Int
        let representations: [TelegramMediaImageRepresentation]
    }

    private struct Preview {
        let mediaIndex: Int
        let image: CGImage
    }

    private enum Destination {
        case clipboard
        case file
    }

    private static let previewQueue = Queue(name: "MessageShotPreviews")

    static func menuItem(for message: Message, selection: Set<MessageId>, selectedMessages: [Message], cachedData: CachedPeerData?, chatTheme: TelegramPresentationTheme?, interaction: ChatInteraction) -> ContextMenuItem? {
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
            export(ids: ids, selection: selection, chatTheme: chatTheme, interaction: interaction, destination: .clipboard)
        }, itemImage: MenuAnimation.menu_copy_media.value))
        menu.addItem(ContextMenuItem(localizedString("Gergram.Chat.MessageShotSave"), handler: { [weak interaction] in
            guard let interaction else { return }
            export(ids: ids, selection: selection, chatTheme: chatTheme, interaction: interaction, destination: .file)
        }, itemImage: MenuAnimation.menu_save_as.value))
        menu.addItem(ContextSeparatorItem())
        let options = MessageShotOptions()
        menu.addItem(ContextMenuItem(localizedString("Gergram.Chat.MessageShotShowTimestamps"), handler: {
            var options = MessageShotOptions()
            options.showsTimestamps.toggle()
            options.save()
        }, state: options.showsTimestamps ? .on : .off))
        menu.addItem(ContextMenuItem(localizedString("Gergram.Chat.MessageShotShowBackground"), handler: {
            var options = MessageShotOptions()
            options.showsBackground.toggle()
            options.save()
        }, state: options.showsBackground ? .on : .off))
        if messages.contains(where: { reactions(for: $0, accountPeerId: interaction.interactionContext.peerId).contains(where: { $0.count > 0 }) }) {
            menu.addItem(ContextMenuItem(localizedString("Gergram.Chat.MessageShotShowReactions"), handler: {
                var options = MessageShotOptions()
                options.showsReactions.toggle()
                options.save()
            }, state: options.showsReactions ? .on : .off))
        }
        let themeItem = ContextMenuItem(localizedString("Gergram.Chat.MessageShotTheme"), handler: {})
        let themes = ContextMenu()
        for choice in MessageShotOptions.Theme.allCases {
            themes.addItem(ContextMenuItem(themeTitle(choice), handler: {
                var options = MessageShotOptions()
                options.theme = choice
                options.save()
            }, state: options.theme == choice ? .on : .off))
        }
        themeItem.submenu = themes
        menu.addItem(themeItem)
        let item = ContextMenuItem(localizedString("Gergram.Chat.MessageShot"), handler: {}, itemImage: MenuAnimation.menu_copy_media.value)
        item.submenu = menu
        return item
    }

    private static func themeTitle(_ theme: MessageShotOptions.Theme) -> String {
        switch theme {
        case .current: return localizedString("Gergram.Chat.MessageShotThemeCurrent")
        case .dayClassic: return strings().appearanceSettingsColorThemeDayClassic
        case .day: return strings().appearanceSettingsColorThemeDay
        case .dark: return strings().appearanceSettingsColorThemeDark
        case .nightAccent: return strings().appearanceSettingsColorThemeNightAccent
        }
    }

    private static func reactions(for message: Message, accountPeerId: PeerId) -> [MessageReaction] {
        guard message.id.peerId != accountPeerId else { return [] }
        return message.effectiveReactions(accountPeerId, isTags: false)?.reactions ?? []
    }

    private static func reactionLabel(_ reaction: MessageReaction.Reaction, message: Message) -> String {
        switch reaction {
        case let .builtin(emoji):
            return emoji
        case let .custom(fileId):
            let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
            let file = message.associatedMedia[mediaId] as? TelegramMediaFile
            if let text = file?.customEmojiText, text.utf16.count <= 32, text.isSingleEmoji {
                return text
            }
            return localizedString("Gergram.Chat.MessageShotCustomReactions")
        case .stars:
            return "⭐"
        }
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
              message.adAttribute == nil, message.paidContent == nil,
              message.activeEphemeralReplacementMessage == nil, !message.flags.contains(.Sending),
              canForwardMessage(message, chatInteraction: interaction),
              !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute || $0 is RichTextMessageAttribute }) else {
            return false
        }

        return (!message.text.isEmpty || message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile })) && message.media.allSatisfy {
            $0 is TelegramMediaImage || $0 is TelegramMediaFile || $0 is TelegramMediaWebpage
        }
    }

    private static func supportsPreview(_ message: Message, interaction: ChatInteraction) -> Bool {
        !message.isMediaSpoilered && !message.isSensitiveContent(platform: "ios", contentSettings: interaction.interactionContext.contentSettings)
    }

    private static func previewRequest(for message: Message, interaction: ChatInteraction) -> PreviewRequest? {
        guard supportsPreview(message, interaction: interaction) else { return nil }
        for (index, media) in message.media.enumerated() {
            let representations: [TelegramMediaImageRepresentation]
            if let image = media as? TelegramMediaImage {
                representations = image.representations
            } else if let file = media as? TelegramMediaFile, file.isVideo {
                representations = file.previewRepresentations
            } else {
                continue
            }
            if !representations.isEmpty {
                return PreviewRequest(id: message.id, mediaIndex: index, representations: representations)
            }
        }
        return nil
    }

    private static func decodePreviews(_ requests: [PreviewRequest], mediaBox: MediaBox) -> [MessageId: Preview] {
        var previews: [MessageId: Preview] = [:]
        for request in requests {
            let representations = request.representations.sorted {
                Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height)
            }
            for representation in representations.prefix(6) {
                if let path = mediaBox.completedResourcePath(representation.resource),
                   let image = MessageShotRenderer.thumbnail(at: path) {
                    previews[request.id] = Preview(mediaIndex: request.mediaIndex, image: image)
                    break
                }
            }
        }
        return previews
    }

    private static func supportsSnapshot(_ snapshot: Snapshot, ids: Set<MessageId>, interaction: ChatInteraction) -> Bool {
        Set(snapshot.messages.map(\.id)) == ids && snapshot.messages.allSatisfy {
            supportsMessage($0, interaction: interaction, cachedData: snapshot.cachedData)
        }
    }

    private static func export(ids: Set<MessageId>, selection: Set<MessageId>, chatTheme: TelegramPresentationTheme?, interaction: ChatInteraction, destination: Destination) {
        guard supportsChat(interaction), (interaction.presentation.selectionState?.selectedIds ?? []) == selection else { return }

        let options = MessageShotOptions()
        let presentationTheme = chatTheme ?? theme
        let palette = options.theme.palette(current: presentationTheme.colors)
        let context = interaction.interactionContext
        let location = interaction.chatLocation
        let mode = interaction.mode
        let peerId = location.peerId
        let refreshRequired = peerId.namespace == Namespaces.Peer.CloudUser && peerId != context.peerId

        func isCurrent(_ interaction: ChatInteraction) -> Bool {
            interaction.canAnimateUpdates() && supportsChat(interaction)
                && interaction.chatLocation == location && interaction.mode == mode
                && (interaction.presentation.selectionState?.selectedIds ?? []) == selection
        }

        func readMessages() -> Signal<Snapshot?, NoError> {
            return context.account.postbox.transaction { transaction in
                guard let peer = transaction.getPeer(peerId) else { return nil }
                let cachedData = transaction.getPeerCachedData(peerId: peerId)
                guard (!refreshRequired || cachedData is CachedUserData), !peerIsRestricted(peer, cachedData: cachedData) else {
                    return nil
                }
                return (ids.compactMap { transaction.getMessage($0) }, cachedData)
            }
        }

        func unchanged(_ current: Snapshot, since previous: Snapshot) -> Bool {
            let versions = Dictionary(uniqueKeysWithValues: previous.messages.map { ($0.id, $0.stableVersion) })
            return current.messages.count == versions.count && current.messages.allSatisfy { versions[$0.id] == $0.stableVersion }
        }

        let refresh = refreshRequired ? context.engine.peers.fetchAndUpdateCachedPeerData(peerId: peerId) : .single(true)
        let load = refresh
        |> take(1)
        |> mapToSignal { fresh in fresh ? readMessages() : .single(nil) }
        |> deliverOnMainQueue
        |> mapToSignal { [weak interaction] snapshot -> Signal<PreparedShot?, NoError> in
            guard let interaction, isCurrent(interaction) else { return .complete() }
            guard let snapshot, supportsSnapshot(snapshot, ids: ids, interaction: interaction) else { return .single(nil) }

            let requests = snapshot.messages.compactMap { previewRequest(for: $0, interaction: interaction) }
            guard !requests.isEmpty else { return .single((snapshot, [:])) }

            let mediaBox = context.account.postbox.mediaBox
            return Signal<[PreviewRequest], NoError>.single(requests)
            |> deliverOn(previewQueue)
            |> map { decodePreviews($0, mediaBox: mediaBox) }
            |> mapToSignal { previews in
                readMessages() |> map { current -> PreparedShot? in
                    guard let current, unchanged(current, since: snapshot) else { return nil }
                    return (current, previews)
                }
            }
        }
        |> deliverOnMainQueue

        _ = load.startStandalone(next: { [weak interaction] result in
            guard let interaction, isCurrent(interaction) else { return }

            guard let (snapshot, previews) = result, supportsSnapshot(snapshot, ids: ids, interaction: interaction) else {
                showModalText(for: context.window, text: localizedString("Gergram.Chat.MessageShotUnavailable"))
                return
            }
            let canvasBackground = options.showsBackground ? palette.background : nil
            guard snapshot.messages.reduce(0, { $0 + $1.text.utf16.count }) <= 16_000,
                  let png = MessageShotRenderer.png(rows: rows(for: snapshot.messages, previews: previews, interaction: interaction, options: options, palette: palette, fontSize: presentationTheme.fontSize), background: canvasBackground) else {
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
                save(png, in: context.window) { [weak interaction] in
                    readMessages()
                    |> deliverOnMainQueue
                    |> map { [weak interaction] current -> Bool? in
                        guard let interaction, isCurrent(interaction) else { return nil }
                        guard let current, unchanged(current, since: snapshot),
                              supportsSnapshot(current, ids: ids, interaction: interaction) else { return false }
                        return previews.isEmpty || current.messages.allSatisfy { previews[$0.id] == nil || supportsPreview($0, interaction: interaction) }
                    }
                }
            }
        })
    }

    private static func save(_ png: Data, in window: Window, validate: @escaping () -> Signal<Bool?, NoError>) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Message Shot.png"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png]
        } else {
            panel.allowedFileTypes = ["png"]
        }
        panel.beginSheetModal(for: window) { [weak window] response in
            guard response == .OK, let url = panel.url, window != nil else { return }
            _ = validate().startStandalone(next: { [weak window] valid in
                guard let window, let valid else { return }
                guard valid else {
                    showModalText(for: window, text: localizedString("Gergram.Chat.MessageShotUnavailable"))
                    return
                }
                do {
                    try png.write(to: url, options: .atomic)
                } catch {
                    showModalText(for: window, text: localizedString("Gergram.Chat.MessageShotSaveFailed"))
                }
            })
        }
    }

    private static func rows(for messages: [Message], previews: [MessageId: Preview], interaction: ChatInteraction, options: MessageShotOptions, palette: ColorPalette, fontSize: CGFloat) -> [MessageShotRenderer.Row] {
        let context = interaction.interactionContext
        let colors = TelegramChatColors(palette, true)
        return messages.sorted { $0.index < $1.index }.map { message in
            let incoming = message.isIncoming(context.account, true)
            let title = options.headerTitle(
                author: message.effectiveAuthor?.displayTitle,
                timestamp: DateSelectorUtil.chatFullDateFormatter.string(
                    from: Date(timeIntervalSince1970: TimeInterval(message.timestamp) - context.timeDifference)
                )
            )
            let secondary = colors.grayText(incoming, true)
            let header = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: secondary])

            let entityAttributes = message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }
            let spoilerRanges = entityAttributes.flatMap { attribute in
                attribute.entities.compactMap { entity -> Range<Int>? in
                    if case .Spoiler = entity.type { return entity.range }
                    return nil
                }
            }
            let sourceText: String
            let sourceAttributes: [MessageAttribute]
            let sourceMessage: Message?
            if spoilerRanges.isEmpty {
                sourceText = message.text
                sourceAttributes = message.attributes
                sourceMessage = message
            } else {
                let redaction = MessageShotRenderer.SpoilerRedaction(text: message.text, spoilerRanges: spoilerRanges)
                let safeEntities = (entityAttributes.first?.entities ?? []).filter { redaction.permitsEntity(in: $0.range) }
                sourceText = redaction.text
                sourceAttributes = [TextEntitiesMessageAttribute(entities: safeEntities)]
                sourceMessage = nil
            }
            let text = ChatMessageItem.applyMessageEntities(with: sourceAttributes, for: sourceText, message: sourceMessage, context: context, fontSize: fontSize, openInfo: { _, _, _, _ in }, textColor: colors.textColor(incoming, true), linkColor: colors.linkColor(incoming, true), monospacedPre: colors.monospacedPreColor(incoming, true), monospacedCode: colors.monospacedCodeColor(incoming, true), blockColor: .init(main: palette.accent), isDark: palette.isDark, bubbled: true, ignoreLinks: true)
            let preview = supportsPreview(message, interaction: interaction) ? previews[message.id] : nil
            let attachments = message.media.enumerated().compactMap { index, media -> MessageShotRenderer.Attachment? in
                let label: String
                if media is TelegramMediaImage {
                    label = strings().chatListPhoto
                } else if let file = media as? TelegramMediaFile {
                    label = file.isVideo ? strings().chatListVideo : (file.isVoice ? strings().chatListVoice : localizedString("Gergram.Chat.MessageShotAttachment"))
                } else {
                    return nil
                }
                let placeholder = NSAttributedString(string: "[\(label)]", attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: secondary])
                return MessageShotRenderer.Attachment(label: placeholder, thumbnail: preview.flatMap { $0.mediaIndex == index ? $0.image : nil })
            }
            let footer: NSAttributedString?
            if options.showsReactions {
                let summary = options.reactionSummary(reactions(for: message, accountPeerId: context.peerId).sorted(by: <).lazy.map {
                    (label: reactionLabel($0.value, message: message), count: Int($0.count))
                })
                footer = NSAttributedString(string: summary, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary])
            } else {
                footer = nil
            }
            return MessageShotRenderer.Row(header: header, body: text, background: colors.bubbleBackgroundColor(incoming, true), attachments: attachments, footer: footer)
        }
    }
}
