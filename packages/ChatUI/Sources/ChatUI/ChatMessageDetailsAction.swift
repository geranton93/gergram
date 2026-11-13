import Foundation
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
    static func menuItem(for message: Message, cachedData: CachedPeerData?, interaction: ChatInteraction) -> ContextMenuItem? {
        guard supportsChat(interaction), let peer = message.peers[message.id.peerId],
              supportsMessage(message, peer: peer, cachedData: cachedData, interaction: interaction) else {
            return nil
        }

        let id = message.id
        let location = interaction.chatLocation
        let mode = interaction.mode
        let details = Self.details(for: message, interaction: interaction)
        let formatter = DateSelectorUtil.chatFullDateFormatter
        let menu = ContextMenu()
        for field in ChatMessageDetails.Field.allCases {
            guard let value = details.value(for: field, dateFormatter: formatter) else { continue }
            let label = localizedString("Gergram.Chat.MessageDetails\(field.rawValue)")
            let title = String(format: localizedString("Gergram.Chat.MessageDetailsField"), label, field.menuValue(value))
            menu.addItem(ContextMenuItem(title, handler: { [weak interaction] in
                guard let interaction, interaction.chatLocation == location, interaction.mode == mode else { return }
                copy(field, from: id, interaction: interaction)
            }, itemImage: MenuAnimation.menu_copy.value, removeTail: false))
        }

        let item = ContextMenuItem(localizedString("Gergram.Chat.MessageDetails"), itemImage: MenuAnimation.menu_show_info.value)
        item.submenu = menu
        return item
    }

    private static func supportsChat(_ interaction: ChatInteraction) -> Bool {
        let context = interaction.interactionContext
        guard !interaction.isLogInteraction, !context.isFrozen, (context.isCurrent || context.isExternal),
              context.window.isVisible, interaction.presentation.reportMode == nil, interaction.presentation.state != .selecting,
              !interaction.presentation.isNotAccessible, interaction.canAnimateUpdates() else {
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

    private static func details(for message: Message, interaction: ChatInteraction) -> ChatMessageDetails {
        let forwarded: Int32? = message.forwardInfo.flatMap { info in
            info.psaType?.isEmpty == false || message.media.contains(where: { $0 is TelegramMediaStory }) ? nil : info.date
        }
        return ChatMessageDetails(
            id: message.id.id,
            sentAt: message.timestamp,
            editedAt: message.editedAttribute?.date,
            forwardedAt: forwarded,
            views: message.attributes.lazy.compactMap { ($0 as? ViewCountMessageAttribute)?.count }.first,
            forwards: message.attributes.lazy.compactMap { ($0 as? ForwardCountMessageAttribute)?.count }.first,
            media: mediaDetails(
                for: message.media,
                isConcealed: message.isMediaSpoilered || message.isSensitiveContent(
                    platform: "ios", contentSettings: interaction.interactionContext.contentSettings
                )
            )
        )
    }

    static func mediaDetails(for attachments: [Media], isConcealed: Bool) -> ChatMessageDetails.MediaDetails? {
        guard !isConcealed else { return nil }

        for media in attachments {
            if let file = media as? TelegramMediaFile, let resource = file.resource as? CloudDocumentMediaResource {
                return .init(
                    fileSize: file.size.flatMap { $0 > 0 ? $0 : nil } ?? resource.size,
                    mimeType: file.mimeType,
                    fileName: file.fileName,
                    dimensions: file.dimensions.map { ($0.width, $0.height) },
                    dataCenter: resource.datacenterId
                )
            }
            if let image = media as? TelegramMediaImage {
                let videos = image.videoRepresentations.compactMap {
                    imageDetails(resource: $0.resource, dimensions: $0.dimensions, mimeType: "video/mp4")
                }
                if let video = videos.max(by: { $0.pixelArea < $1.pixelArea }) {
                    return video
                }
                let photos = image.representations.compactMap {
                    imageDetails(resource: $0.resource, dimensions: $0.dimensions, mimeType: "image/jpeg")
                }
                if let photo = photos.max(by: { $0.pixelArea < $1.pixelArea }) {
                    return photo
                }
            }
        }
        return nil
    }

    private static func imageDetails(resource: TelegramMediaResource, dimensions: PixelDimensions, mimeType: String) -> ChatMessageDetails.MediaDetails? {
        let dataCenter = (resource as? CloudPhotoSizeMediaResource)?.datacenterId ?? (resource as? CloudFileMediaResource)?.datacenterId
        guard let dataCenter, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return .init(
            fileSize: resource.size,
            mimeType: mimeType,
            fileName: nil,
            dimensions: (dimensions.width, dimensions.height),
            dataCenter: dataCenter
        )
    }

    private static func copy(_ field: ChatMessageDetails.Field, from id: MessageId, interaction: ChatInteraction) {
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
                  supportsMessage(message, peer: peer, cachedData: cachedData, interaction: interaction),
                  let value = details(for: message, interaction: interaction).value(for: field, dateFormatter: DateSelectorUtil.chatFullDateFormatter) else {
                return
            }
            copyToClipboard(value)
            showModalText(for: context.window, text: strings().contextAlertCopied)
        })
    }
}
