import AppKit
import ChatModeTypes
import LocalAnimations
import Localization
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUtils
import TGUIKit

enum ChatMessageDetailsAction {
    enum AttachmentID: Hashable {
        case file(MediaId)
        case image(MediaId)
    }

    struct AttachmentDetails {
        let selection: AttachmentSelection
        let details: ChatMessageDetails.MediaDetails
    }

    struct AttachmentSelection: Equatable {
        let id: AttachmentID
        let resourceId: MediaResourceId
    }

    static func menuItem(for message: Message, cachedData: CachedPeerData?, interaction: ChatInteraction) -> ContextMenuItem? {
        guard supportsChat(interaction), let peer = message.peers[message.id.peerId],
              supportsMessage(message, peer: peer, cachedData: cachedData, interaction: interaction) else {
            return nil
        }

        let id = message.id
        let location = interaction.chatLocation
        let mode = interaction.mode
        let details = Self.details(for: message)
        let formatter = DateSelectorUtil.chatFullDateFormatter
        let menu = ContextMenu()

        func addField(_ field: ChatMessageDetails.Field, value: String?, to targetMenu: ContextMenu, attachment: AttachmentSelection? = nil) {
            guard let value else { return }
            let label = localizedString("Gergram.Chat.MessageDetails\(field.rawValue)")
            let title = String(format: localizedString("Gergram.Chat.MessageDetailsField"), label, field.menuValue(value))
            let item = ContextMenuItem(title, handler: { [weak interaction] in
                guard let interaction, interaction.chatLocation == location, interaction.mode == mode else { return }
                copy(field, from: id, attachment: attachment, interaction: interaction)
            }, itemImage: MenuAnimation.menu_copy.value, removeTail: false)
            setLiteralTitle(title, for: item, in: targetMenu)
            targetMenu.addItem(item)
        }

        for field in ChatMessageDetails.Field.messageFields {
            addField(field, value: details.value(for: field, dateFormatter: formatter), to: menu)
        }
        let attachments = attachmentDetails(for: message.media, isConcealed: isConcealed(message, interaction: interaction))
        for (index, attachment) in attachments.enumerated() {
            let fieldsMenu = attachments.count == 1 ? menu : ContextMenu()
            for field in ChatMessageDetails.Field.attachmentFields {
                addField(field, value: attachment.details.value(for: field), to: fieldsMenu, attachment: attachment.selection)
            }
            if attachments.count > 1 {
                let label = String(format: localizedString("Gergram.Chat.MessageDetailsAttachment"), String(index + 1))
                let title = attachment.details.value(for: .fileName).map {
                    String(format: localizedString("Gergram.Chat.MessageDetailsField"), label, ChatMessageDetails.Field.fileName.menuValue($0))
                } ?? label
                let attachmentItem = ContextMenuItem(title, itemImage: MenuAnimation.menu_file.value, removeTail: false)
                setLiteralTitle(title, for: attachmentItem, in: menu)
                attachmentItem.submenu = fieldsMenu
                menu.addItem(attachmentItem)
            }
        }

        let item = ContextMenuItem(localizedString("Gergram.Chat.MessageDetails"), itemImage: MenuAnimation.menu_show_info.value)
        item.submenu = menu
        return item
    }

    private static func setLiteralTitle(_ title: String, for item: ContextMenuItem, in menu: ContextMenu) {
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.medium(.text),
            .foregroundColor: menu.presentation.primaryColor(item)
        ])
    }

    private static func supportsChat(_ interaction: ChatInteraction) -> Bool {
        let context = interaction.interactionContext
        guard !interaction.isLogInteraction, !interaction.isGlobalSearchMessage, !context.isFrozen, (context.isCurrent || context.isExternal),
              context.window.isVisible, interaction.presentation.reportMode == nil, interaction.presentation.state != .selecting,
              !interaction.presentation.isNotAccessible, interaction.canInspectMessageDetails() else {
            return false
        }
        switch interaction.mode {
        case .history, .thread:
            return true
        default:
            return false
        }
    }

    private static func supportsMessage(_ message: Message, peer: Peer, cachedData: CachedPeerData?, interaction: ChatInteraction) -> Bool {
        let peerId = message.id.peerId
        let context = interaction.interactionContext
        guard peerId == interaction.peerId, peerId.namespace != Namespaces.Peer.SecretChat,
              message.id.namespace == Namespaces.Message.Cloud, message.id.id > 0,
              peerId.namespace != Namespaces.Peer.CloudUser || peerId == context.peerId || cachedData is CachedUserData,
              peer.restrictionText(context.contentSettings) == nil,
              !peer.isCopyProtectionEnabled, !peer.isCopyProtected(cachedData: cachedData),
              !message.isCopyProtected(cachedData: cachedData), !message.containsSecretMedia,
              message.autoclearTimeout == nil, message.autoremoveAttribute == nil,
              message.activeEphemeralReplacementMessage == nil, message.paidContent == nil,
              !message.flags.contains(.Sending),
              !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute }) else {
            return false
        }
        return canForwardMessage(message, chatInteraction: interaction)
    }

    private static func details(for message: Message) -> ChatMessageDetails {
        let forwarded: Int32? = message.forwardInfo.flatMap { info in
            info.psaType?.isEmpty == false || message.media.contains(where: { $0 is TelegramMediaStory }) ? nil : info.date
        }
        return ChatMessageDetails(
            id: message.id.id,
            sentAt: message.timestamp,
            editedAt: message.editedAttribute?.date,
            forwardedAt: forwarded,
            views: message.attributes.lazy.compactMap { ($0 as? ViewCountMessageAttribute)?.count }.first,
            forwards: message.attributes.lazy.compactMap { ($0 as? ForwardCountMessageAttribute)?.count }.first
        )
    }

    private static func isConcealed(_ message: Message, interaction: ChatInteraction) -> Bool {
        message.isMediaSpoilered || message.isSensitiveContent(platform: "ios", contentSettings: interaction.interactionContext.contentSettings)
    }

    static func attachmentDetails(for attachments: [Media], isConcealed: Bool) -> [AttachmentDetails] {
        guard !isConcealed else { return [] }
        var ids: Set<AttachmentID> = []
        var ambiguousIds: Set<AttachmentID> = []
        var result: [AttachmentDetails] = []
        for media in attachments {
            let id: AttachmentID
            if let file = media as? TelegramMediaFile {
                id = .file(file.fileId)
            } else if let image = media as? TelegramMediaImage {
                id = .image(image.imageId)
            } else {
                continue
            }
            guard ids.insert(id).inserted else {
                ambiguousIds.insert(id)
                continue
            }
            if let (resourceId, details) = mediaDetails(for: media), ChatMessageDetails.Field.attachmentFields.contains(where: { details.value(for: $0) != nil }) {
                result.append(.init(selection: .init(id: id, resourceId: resourceId), details: details))
            }
        }

        return result.filter { !ambiguousIds.contains($0.selection.id) }
    }

    private static func mediaDetails(for media: Media) -> (MediaResourceId, ChatMessageDetails.MediaDetails)? {
        if let file = media as? TelegramMediaFile, let resource = file.resource as? CloudDocumentMediaResource {
            return (resource.id, .init(
                fileSize: file.size.flatMap { $0 > 0 ? $0 : nil } ?? resource.size,
                mimeType: file.mimeType,
                fileName: file.fileName,
                dimensions: file.dimensions.map { ($0.width, $0.height) },
                dataCenter: resource.datacenterId
            ))
        }
        if let image = media as? TelegramMediaImage {
            if let video = image.video, let details = mediaDetails(for: video) {
                return details
            }
            let videos = image.videoRepresentations.lazy.compactMap {
                imageDetails(resource: $0.resource, dimensions: $0.dimensions, mimeType: "video/mp4")
            }
            if let video = videos.max(by: { $0.1.pixelArea < $1.1.pixelArea }) {
                return video
            }
            return image.representations.lazy.compactMap {
                imageDetails(resource: $0.resource, dimensions: $0.dimensions, mimeType: "image/jpeg")
            }.max(by: { $0.1.pixelArea < $1.1.pixelArea })
        }
        return nil
    }

    private static func imageDetails(resource: TelegramMediaResource, dimensions: PixelDimensions, mimeType: String) -> (MediaResourceId, ChatMessageDetails.MediaDetails)? {
        let dataCenter = (resource as? CloudPhotoSizeMediaResource)?.datacenterId ?? (resource as? CloudFileMediaResource)?.datacenterId
        guard let dataCenter, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return (resource.id, .init(
            fileSize: resource.size,
            mimeType: mimeType,
            fileName: nil,
            dimensions: (dimensions.width, dimensions.height),
            dataCenter: dataCenter
        ))
    }

    private static func copy(_ field: ChatMessageDetails.Field, from id: MessageId, attachment: AttachmentSelection?, interaction: ChatInteraction) {
        guard supportsChat(interaction), interaction.peerId == id.peerId else { return }
        let location = interaction.chatLocation
        let mode = interaction.mode
        let context = interaction.interactionContext
        let load = context.account.postbox.transaction { transaction -> (Message, Peer, CachedPeerData?)? in
            guard let message = transaction.getMessage(id), let peer = transaction.getPeer(id.peerId) else { return nil }
            return (message, peer, transaction.getPeerCachedData(peerId: id.peerId))
        }

        _ = (load |> deliverOnMainQueue).startStandalone(next: { [weak interaction] result in
            guard let interaction, supportsChat(interaction),
                  interaction.chatLocation == location, interaction.mode == mode,
                  let (message, peer, cachedData) = result,
                  supportsMessage(message, peer: peer, cachedData: cachedData, interaction: interaction) else {
                return
            }
            let value: String?
            if let attachment {
                value = attachmentValue(for: field, selection: attachment, in: message.media, isConcealed: isConcealed(message, interaction: interaction))
            } else {
                value = details(for: message).value(for: field, dateFormatter: DateSelectorUtil.chatFullDateFormatter)
            }
            guard let value else { return }
            copyToClipboard(value)
            showModalText(for: context.window, text: strings().contextAlertCopied)
        })
    }

    static func attachmentValue(for field: ChatMessageDetails.Field, selection: AttachmentSelection, in attachments: [Media], isConcealed: Bool) -> String? {
        attachmentDetails(for: attachments, isConcealed: isConcealed).first { $0.selection == selection }?.details.value(for: field)
    }
}
