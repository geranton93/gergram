import AlertsUI
import AppKit
import ChatHistoryModel
import ChatModeTypes
import Foundation
import InAppSettings
import Localization
import LocalAnimations
import MessageUtils
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramMediaUtils
import TelegramUtils
import TGUIKit

struct ChatRepeatMessagePayload: Equatable {
    let text: String
    let entities: [MessageTextEntity]
    let photoId: MediaId?

    init?(text: String, entities: [MessageTextEntity], photoId: MediaId? = nil, captionLimit: Int = 4096) {
        let utf16 = text.utf16
        let length = utf16.count
        guard length <= 4096 else { return nil }
        if photoId != nil {
            guard length <= captionLimit else { return nil }
        } else if !text.unicodeScalars.contains(where: {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }) {
            return nil
        }
        for entity in entities {
            let range = entity.range
            guard range.lowerBound >= 0, range.upperBound <= length, !range.isEmpty,
                  Self.isScalarBoundary(range.lowerBound, in: utf16),
                  Self.isScalarBoundary(range.upperBound, in: utf16) else { return nil }
            switch entity.type {
            case .Unknown, .PhoneNumber, .Custom, .TextMention, .CustomEmoji:
                return nil
            default:
                break
            }
        }
        self.text = text
        self.entities = entities
        self.photoId = photoId
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text.utf16.elementsEqual(rhs.text.utf16) && lhs.entities == rhs.entities && lhs.photoId == rhs.photoId
    }

    private static func isScalarBoundary(_ offset: Int, in text: String.UTF16View) -> Bool {
        if offset == text.count { return true }
        let unit = text[text.index(text.startIndex, offsetBy: offset)]
        return !(0xDC00...0xDFFF).contains(unit)
    }

    func outgoing(source: Message, threadId: Int64?, threadRoot: MessageId?, silent: Bool) -> EnqueueMessage? {
        let mediaReference: AnyMediaReference?
        if let photoId {
            let reference = MessageReference(source)
            guard let image = Self.photo(in: source), image.imageId == photoId, reference.id == source.id else { return nil }
            mediaReference = .message(message: reference, media: image)
        } else {
            guard source.media.isEmpty else { return nil }
            mediaReference = nil
        }
        var attributes: [MessageAttribute] = [
            TextEntitiesMessageAttribute(entities: entities),
            OutgoingContentInfoMessageAttribute(flags: [.disableLinkPreviews])
        ]
        if silent {
            attributes.append(NotificationInfoMessageAttribute(flags: [.muted]))
        }
        return .message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference,
                        threadId: threadId, replyToMessageId: threadRoot.map { .init(messageId: $0, quote: nil, innerSubject: nil) },
                        replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
    }

    static func photo(in message: Message) -> TelegramMediaImage? {
        guard message.media.count == 1, let image = message.media.first as? TelegramMediaImage,
              image.imageId.namespace == Namespaces.Media.CloudImage, image.imageId.id > 0,
              let reference = image.reference,
              case let .cloud(id, _, fileReference) = reference, id == image.imageId.id, fileReference?.isEmpty == false,
              image.representations.contains(where: { $0.resource is CloudPhotoSizeMediaResource }),
              image.video == nil, image.videoRepresentations.isEmpty, image.emojiMarkup == nil else {
            return nil
        }
        return image
    }
}

final class ChatRepeatMessageAction {
    private struct Scope: Equatable {
        let location: ChatLocation
        let mode: ChatMode
    }

    private enum Stage {
        case idle
        case confirming
        case loading
        case sending
    }

    private var stage = Stage.idle
    private var generation = UUID()
    private let confirmation = ChatMediaSendConfirmation()
    private let lifetimeObservation = MetaDisposable()
    private let work = MetaDisposable()

    deinit {
        lifetimeObservation.dispose()
        work.dispose()
    }

    func menuItem(for message: Message, interaction: ChatInteraction) -> ContextMenuItem? {
        let state = interaction.presentation
        guard stage == .idle, let scope = Self.scope(interaction),
              let peer = interaction.peer, let original = Self.payload(for: message, in: scope, peer: peer, cachedData: state.cachedData, interaction: interaction) else {
            return nil
        }
        let id = message.id
        return ContextMenuItem(localizedString("Gergram.Chat.RepeatMessage"), handler: { [weak interaction, weak self] in
            guard let interaction else { return }
            self?.start(id: id, original: original, scope: scope, interaction: interaction)
        }, itemImage: MenuAnimation.menu_reload.value)
    }

    func cancel() {
        guard stage == .confirming || stage == .loading else { return }
        reset()
    }

    private static func scope(_ interaction: ChatInteraction) -> Scope? {
        let context = interaction.interactionContext
        let state = interaction.presentation
        let location = interaction.chatLocation
        let mode = interaction.mode
        guard (context.isCurrent || context.isExternal), context.window.isVisible, !context.isFrozen,
              interaction.canAnimateUpdates(), !interaction.isLogInteraction, !interaction.isGlobalSearchMessage,
              state.state == .normal, state.reportMode == nil, state.selectionState == nil, !state.searchMode.inSearch,
              !state.isNotAccessible, state.isBlocked != true, !state.threadedBot, !state.isMonoforum,
              state.currentSendAsPeerId == nil || state.currentSendAsPeerId == context.peerId,
              state.slowMode == nil, !state.slowModeMultipleLocked, state.sendPaidMessageStars == nil,
              state.interfaceState.suggestPost == nil,
              let peer = interaction.peer, Self.supportsPeer(peer, in: location, mode: mode, interaction: interaction),
              canSend(to: peer, cachedData: state.cachedData, interaction: interaction) else { return nil }
        return Scope(location: location, mode: mode)
    }

    private static func supportsPeer(_ peer: Peer, in location: ChatLocation, mode: ChatMode, interaction: ChatInteraction) -> Bool {
        guard peer.id == location.peerId, !peer.isMonoForum,
              peer.restrictionText(interaction.interactionContext.contentSettings) == nil else { return false }
        if let channel = peer as? TelegramChannel {
            guard case .group = channel.info, channel.participationStatus == .member else { return false }
        } else if !(peer is TelegramUser || peer is TelegramGroup) {
            return false
        }
        switch (mode, location) {
        case (.history, .peer) where !peer.isForumOrMonoForum:
            return true
        case let (.history, .thread(thread)), let (.thread(.topic), .thread(thread)):
            return peer.isForumOrMonoForum && thread.isForumPost && !thread.isNotAvailable
                && thread.threadId > 0 && thread.threadId != Message.newTopicThreadId
                && thread.effectiveTopId.peerId == location.peerId
        default:
            return false
        }
    }

    private static func canSend(to peer: Peer, cachedData: CachedPeerData?, interaction: ChatInteraction) -> Bool {
        let state = interaction.presentation
        if state.threadInfo?.isClosed == true, !peer.isAdmin, state.threadInfo?.isOwnedByMe != true { return false }
        if let data = cachedData as? CachedUserData,
           data.flags.contains(.premiumRequired), !interaction.interactionContext.isPremium { return false }
        if let data = cachedData as? CachedUserData, let price = data.sendPaidMessageStars, price.value > 0 { return false }
        if let channel = peer as? TelegramChannel, !channel.isAdmin, let price = channel.sendPaidMessageStars, price.value > 0 { return false }
        return permissionText(from: peer, for: .banSendText, cachedData: cachedData) == nil
            && peer.canSendMessage(interaction.mode.isThreadMode, threadData: state.threadInfo, cachedData: cachedData)
    }

    private static func payload(for message: Message, in scope: Scope, peer: Peer, cachedData: CachedPeerData?, interaction: ChatInteraction) -> ChatRepeatMessagePayload? {
        let context = interaction.interactionContext
        let state = interaction.presentation
        let id = message.id
        guard id.peerId == scope.location.peerId, id.peerId == peer.id, id.namespace == Namespaces.Message.Cloud,
              id.id > 0, id != scope.location.threadMsgId, message.threadId == scope.location.threadId,
              message.author?.id == context.peerId, !message.effectivelyIncoming(context.peerId),
              !message.flags.contains(.Sending), !message.flags.contains(.Failed), !message.flags.contains(.Unsent),
              message.groupingKey == nil, message.forwardInfo == nil, message.replyMarkup == nil,
              !message.isScheduledMessage, !message.containsSecretMedia, message.adAttribute == nil,
              message.autoclearTimeout == nil, message.autoremoveAttribute == nil, message.activeEphemeralReplacementMessage == nil,
              message.paidContent == nil, message.publishedSuggestedPostMessageAttribute == nil,
              !message.attributes.contains(where: {
                  $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute || $0 is RichTextMessageAttribute
                      || $0 is PaidStarsMessageAttribute || $0 is InlineBotMessageAttribute
              }),
              !peer.isCopyProtectionEnabled, !peer.isCopyProtected(cachedData: cachedData),
              state.peer?.isCopyProtectionEnabled != true, state.peer?.isCopyProtected(cachedData: state.cachedData) != true,
              !message.isCopyProtected(cachedData: cachedData), canForwardMessage(message, chatInteraction: interaction),
              !ChatLocalMessageVisibility.get(context.account).isHidden(message) else { return nil }
        if peer is TelegramUser, peer.id != context.peerId, !(cachedData is CachedUserData) { return nil }
        let entities = message.textEntities?.entities ?? []
        if message.media.isEmpty {
            return ChatRepeatMessagePayload(text: message.text, entities: entities)
        }
        guard let photo = ChatRepeatMessagePayload.photo(in: message), MessageReference(message).id == id,
              !message.isMediaSpoilered, !message.isSensitiveContent(platform: "ios", contentSettings: context.contentSettings),
              let currentPeer = interaction.peer,
              Self.canSendPhoto(photo, to: peer, cachedData: cachedData, interaction: interaction),
              Self.canSendPhoto(photo, to: currentPeer, cachedData: state.cachedData, interaction: interaction) else { return nil }
        let limits = context.premiumLimits
        let captionLimit = Int(context.isPremium ? limits.caption_length_limit_premium : limits.caption_length_limit_default)
        return ChatRepeatMessagePayload(text: message.text, entities: entities, photoId: photo.imageId, captionLimit: captionLimit)
    }

    private static func canSendPhoto(_ photo: TelegramMediaImage, to peer: Peer, cachedData: CachedPeerData?, interaction: ChatInteraction) -> Bool {
        permissionText(from: peer, for: .banSendPhotos, cachedData: cachedData) == nil
            && peer.canSendMessage(interaction.mode.isThreadMode, media: photo, threadData: interaction.presentation.threadInfo, cachedData: cachedData)
    }

    private func start(id: MessageId, original: ChatRepeatMessagePayload, scope: Scope, interaction: ChatInteraction) {
        guard stage == .idle, Self.scope(interaction) == scope else { return }
        stage = .confirming
        let generation = self.generation
        let deferred = interaction.captureDeferredSendAction()
        let context = interaction.interactionContext
        let window = context.window
        let lifetime: Signal<Bool, NoError>
        if context.isExternal {
            lifetime = window.visibility
        } else {
            let accountId = context.account.id
            let active = context.sharedContext.activeAccounts |> map { $0.primary?.id == accountId } |> distinctUntilChanged
            lifetime = combineLatest(window.visibility, active) |> map { $0 && $1 }
        }
        let data = ModalAlertData(title: localizedString("Gergram.Chat.RepeatMessage"),
                                  info: localizedString("Gergram.Chat.RepeatMessageConfirm"),
                                  ok: strings().modalSend, mode: .confirm(text: strings().modalCancel, isThird: false))
        let clear: () -> Void = { [weak self] in
            guard let self, self.generation == generation, self.stage == .confirming else { return }
            self.reset()
        }
        confirmation.start(lifetime: lifetime, present: { accept, cancel, dismiss in
            showDismissableModalAlert(for: window, data: data, completion: { _ in accept() }, cancel: cancel, onDeinit: dismiss)
        }, accepted: { [weak self, weak interaction] in
            guard let self, let interaction, self.generation == generation, self.stage == .confirming else { return }
            guard deferred.isAvailable, Self.scope(interaction) == scope else {
                self.reset()
                return
            }
            self.stage = .loading
            self.lifetimeObservation.set((lifetime |> filter { !$0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
                guard let self, self.generation == generation else { return }
                self.cancel()
            }))
            self.load(id: id, original: original, scope: scope, interaction: interaction, generation: generation, deferred: deferred)
        }, cancelled: clear, dismissed: clear)
    }

    private func load(id: MessageId, original: ChatRepeatMessagePayload, scope: Scope, interaction: ChatInteraction, generation: UUID, deferred: ChatDeferredSendAction) {
        guard self.generation == generation, stage == .loading else { return }
        let context = interaction.interactionContext
        let needsPeerRefresh = id.peerId.namespace == Namespaces.Peer.CloudUser && id.peerId != context.peerId
        let refresh = needsPeerRefresh ? context.engine.peers.fetchAndUpdateCachedPeerData(peerId: id.peerId) : .single(true)
        let load = refresh |> take(1) |> mapToSignal { current -> Signal<(Message, Peer, CachedPeerData?)?, NoError> in
            guard current else { return .single(nil) }
            return context.account.postbox.transaction { transaction in
                guard let message = transaction.getMessage(id), let peer = transaction.getPeer(id.peerId) else { return nil }
                return (message, peer, transaction.getPeerCachedData(peerId: id.peerId))
            }
        } |> deliverOnMainQueue
        let subscription = MetaDisposable()
        work.set(subscription)
        subscription.set(load.start(next: { [weak self, weak interaction] snapshot in
            guard let self, let interaction, self.generation == generation, self.stage == .loading else { return }
            guard deferred.takeIfCurrent(), Self.scope(interaction) == scope else {
                self.reset()
                return
            }
            guard let (message, peer, cachedData) = snapshot,
                  Self.supportsPeer(peer, in: scope.location, mode: scope.mode, interaction: interaction),
                  Self.canSend(to: peer, cachedData: cachedData, interaction: interaction),
                  Self.payload(for: message, in: scope, peer: peer, cachedData: cachedData, interaction: interaction) == original else {
                self.reset()
                alert(for: context.window, info: localizedString("Gergram.Chat.RepeatMessageUnavailable"))
                return
            }
            self.send(original, source: message, scope: scope, interaction: interaction, generation: generation)
        }, completed: { [weak self] in
            guard let self, self.generation == generation, self.stage == .loading else { return }
            self.reset()
        }))
    }

    private func send(_ payload: ChatRepeatMessagePayload, source: Message, scope: Scope, interaction: ChatInteraction, generation: UUID) {
        let peerId = scope.location.peerId
        let silent = interaction.resolvedSendSound().notificationIsSilent ?? FastSettings.isChannelMessagesMuted(peerId)
        guard let message = payload.outgoing(source: source, threadId: scope.location.threadId, threadRoot: scope.location.threadMsgId, silent: silent) else {
            reset()
            return
        }
        stage = .sending
        lifetimeObservation.set(nil)
        let context = interaction.interactionContext
        let subscription = MetaDisposable()
        work.set(subscription)
        let result = Sender.enqueue(message: message, context: context, peerId: peerId) |> take(1)
        subscription.set(result.start(next: { [weak self, weak interaction] ids in
            guard let self, self.generation == generation else { return }
            self.reset()
            guard ids.count == 1, ids[0] != nil else {
                if let interaction, Self.scope(interaction) == scope {
                    alert(for: context.window, info: localizedString("Gergram.Chat.RepeatMessageFailed"))
                }
                return
            }
        }, completed: { [weak self, weak interaction] in
            guard let self, self.generation == generation else { return }
            self.reset()
            if let interaction, Self.scope(interaction) == scope {
                alert(for: context.window, info: localizedString("Gergram.Chat.RepeatMessageFailed"))
            }
        }))
    }

    private func reset() {
        generation = UUID()
        stage = .idle
        confirmation.cancel()
        lifetimeObservation.set(nil)
        work.set(nil)
    }
}
