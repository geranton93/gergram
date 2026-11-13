import AlertsUI
import ChatModeTypes
import Foundation
import Localization
import MessageUtils
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramCore
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils

final class ChatBulkDeleteSelectionAction {
    private typealias Selection = ChatBulkDeleteSelection
    private let load = MetaDisposable()
    private var revision = UUID()

    deinit {
        load.dispose()
    }

    func cancel() {
        revision = UUID()
        load.set(nil)
    }

    func menuItem(
        interaction: ChatInteraction,
        isActive: @escaping () -> Bool,
        history: @escaping () -> ChatHistoryView?,
        ranks: @escaping () -> CachedChannelAdminRanks?
    ) -> ContextMenuItem? {
        guard isActive(), let scope = Self.scope(interaction), history()?.originalView != nil else { return nil }
        let location = interaction.chatLocation
        let mode = interaction.mode
        let datesMenu = ContextMenu()
        for dates in Selection.DateFilter.allCases {
            let dateItem = ContextMenuItem(Self.title(dates), handler: {})
            let mediaMenu = ContextMenu()
            for media in Selection.MediaFilter.allCases {
                mediaMenu.addItem(ContextMenuItem(Self.title(media), handler: { [weak self, weak interaction] in
                    guard let self, let interaction, isActive(), interaction.chatLocation == location,
                          interaction.mode == mode, Self.scope(interaction) == scope else { return }
                    self.review(scope: scope, dates: dates, media: media, interaction: interaction,
                                isActive: isActive, history: history, ranks: ranks)
                }))
            }
            dateItem.submenu = mediaMenu
            datesMenu.addItem(dateItem)
        }
        let item = ContextMenuItem(localizedString("Gergram.Chat.BulkDelete.Menu"), handler: {})
        item.submenu = datesMenu
        return item
    }

    private static func scope(_ interaction: ChatInteraction) -> Selection.Scope? {
        let context = interaction.interactionContext
        let presentation = interaction.presentation
        let location = interaction.chatLocation
        guard (context.isCurrent || context.isExternal), context.window.isVisible, !context.isFrozen,
              !interaction.isLogInteraction, !interaction.disableSelectAbility, !interaction.isGlobalSearchMessage,
              !presentation.isNotAccessible, presentation.reportMode == nil, presentation.selectionState == nil,
              presentation.recordingState == nil, presentation.state == .normal, !presentation.searchMode.inSearch,
              let peer = interaction.peer, peer.id == location.peerId, !peer.isMonoForum,
              peer.restrictionText(context.contentSettings) == nil else { return nil }
        switch peer.id.namespace {
        case Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel:
            break
        default:
            return nil
        }
        if let channel = peer as? TelegramChannel, channel.participationStatus != .member { return nil }
        switch (interaction.mode, location) {
        case (.history, .peer) where !peer.isForumOrMonoForum:
            break
        case let (.history, .thread(thread)), let (.thread(.topic), .thread(thread)):
            guard peer.isForumOrMonoForum, thread.isForumPost, !thread.isNotAvailable,
                  thread.threadId > 0, thread.threadId != Message.newTopicThreadId else { return nil }
            break
        default:
            return nil
        }
        return .init(accountId: context.account.id.int64, authorId: context.peerId,
                     peerId: location.peerId, threadId: location.threadId)
    }

    private static func candidates(_ messages: [Message], interaction: ChatInteraction, ranks: CachedChannelAdminRanks?) -> [Selection.Candidate] {
        let context = interaction.interactionContext
        let visibility = ChatLocalMessageVisibility.get(context.account)
        return messages.compactMap { message in
            guard message.id.namespace == Namespaces.Message.Cloud, message.id.id > 0,
                  message.author?.id == context.peerId, !message.effectivelyIncoming(context.peerId),
                  !message.flags.contains(.Unsent), !message.flags.contains(.Failed), !message.flags.contains(.Sending),
                  message.adAttribute == nil, !message.containsSecretMedia, message.autoclearTimeout == nil,
                  message.autoremoveAttribute == nil, message.activeEphemeralReplacementMessage == nil,
                  message.paidContent == nil, message.publishedSuggestedPostMessageAttribute == nil,
                  !message.attributes.contains(where: { $0 is EphemeralMessageAttribute || $0 is RestrictedContentMessageAttribute }),
                  !message.media.contains(where: { $0 is TelegramMediaAction || $0 is TelegramMediaGiveaway || $0 is TelegramMediaGiveawayResults }),
                  !visibility.isHidden(message),
                  canDeleteMessage(message, account: context.account, chatLocation: interaction.chatLocation, mode: interaction.mode, ranks: ranks) else { return nil }
            return .init(id: message.id, authorId: message.author?.id, threadId: message.threadId,
                         timestamp: message.timestamp, version: message.stableVersion, media: mediaTypes(message))
        }
    }

    private static func loadedMessages(_ history: ChatHistoryView) -> [Message]? {
        guard history.filteredEntries.count <= Selection.scanLimit else { return nil }
        var remaining = Selection.scanLimit - history.filteredEntries.count
        var messages: [Message] = []
        for row in history.filteredEntries {
            switch row.entry {
            case let .MessageEntry(message, _, _, _, _, _, _):
                messages.append(message)
            case let .groupedPhotos(entries, _):
                guard entries.count <= remaining else { return nil }
                remaining -= entries.count
                messages.append(contentsOf: entries.compactMap(\.message))
            default:
                break
            }
        }
        return messages
    }

    private static func mediaTypes(_ message: Message) -> Set<Selection.MediaFilter> {
        return Set(message.media.compactMap { media in
            if media is TelegramMediaImage { return .photos }
            guard let file = media as? TelegramMediaFile else { return nil }
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker { return .stickers }
            if file.isVoice { return .voice }
            if file.isInstantVideo { return .videoMessages }
            if file.mimeType.lowercased() == "image/gif" || (file.isAnimated && file.isVideo) { return .gifs }
            if file.isVideo { return .videos }
            return nil
        })
    }

    private func review(
        scope: Selection.Scope, dates: Selection.DateFilter, media: Selection.MediaFilter,
        interaction: ChatInteraction, isActive: @escaping () -> Bool,
        history: @escaping () -> ChatHistoryView?, ranks: @escaping () -> CachedChannelAdminRanks?
    ) {
        cancel()
        let revision = self.revision
        let context = interaction.interactionContext
        let location = interaction.chatLocation
        let mode = interaction.mode
        let window = context.window
        let title = localizedString("Gergram.Chat.BulkDelete.PreviewTitle")
        guard let historyView = history(), historyView.originalView != nil else { return }
        guard let loaded = Self.loadedMessages(historyView) else {
            alert(for: window, header: title, info: localizedString("Gergram.Chat.BulkDelete.ScanLimit"))
            return
        }
        let result = Selection.preview(scope: scope, dates: dates.range(endingAt: context.timestamp), media: media,
                                       candidates: Self.candidates(loaded, interaction: interaction, ranks: ranks()))
        let preview: Selection.Preview
        switch result {
        case let .ready(value):
            preview = value
        case .empty:
            alert(for: window, header: title, info: localizedString("Gergram.Chat.BulkDelete.NoMatches"))
            return
        case .limitExceeded:
            alert(for: window, header: title, info: translate(key: "Gergram.Chat.BulkDelete.Limit", [Selection.limit]))
            return
        case .scanLimitExceeded:
            alert(for: window, header: title, info: localizedString("Gergram.Chat.BulkDelete.ScanLimit"))
            return
        case .changed:
            alert(for: window, header: title, info: localizedString("Gergram.Chat.BulkDelete.Changed"))
            return
        }

        func isCurrent(_ interaction: ChatInteraction) -> Bool {
            isActive() && interaction.chatLocation == location && interaction.mode == mode && Self.scope(interaction) == scope
        }

        let ids = preview.ids
        verifyAlert(for: window, header: title, information: translate(key: "Gergram.Chat.BulkDelete.PreviewInfo", [ids.count]),
                    ok: localizedString("Gergram.Chat.BulkDelete.Select"), successHandler: { [weak self, weak interaction] _ in
            guard let self, let interaction, self.revision == revision, isCurrent(interaction) else { return }
            let read = context.account.postbox.transaction { transaction -> [Message] in
                guard let peer = transaction.getPeer(scope.peerId), peer.restrictionText(context.contentSettings) == nil,
                      (peer as? TelegramChannel).map({ $0.participationStatus == .member }) ?? true else { return [] }
                return ids.compactMap { transaction.getMessage($0) }
            } |> deliverOnMainQueue
            self.load.set(read.start(next: { [weak self, weak interaction] messages in
                guard let self, let interaction, self.revision == revision, isCurrent(interaction) else { return }
                self.revision = UUID()
                guard let historyView = history(), let loaded = Self.loadedMessages(historyView),
                      preview.confirmedIds(in: scope, candidates: Self.candidates(loaded.filter { ids.contains($0.id) }, interaction: interaction, ranks: ranks())) != nil,
                      let ids = preview.confirmedIds(in: scope, candidates: Self.candidates(messages, interaction: interaction, ranks: ranks())) else {
                    alert(for: window, header: title, info: localizedString("Gergram.Chat.BulkDelete.Changed"))
                    return
                }
                interaction.update { $0.withSelectionState().withUpdatedSelectedMessages(ids) }
            }))
        })
    }

    private static func title(_ dates: Selection.DateFilter) -> String {
        switch dates {
        case .all: return localizedString("Gergram.Chat.BulkDelete.AllDates")
        case .pastWeek: return localizedString("Gergram.Chat.BulkDelete.PastWeek")
        case .pastMonth: return localizedString("Gergram.Chat.BulkDelete.PastMonth")
        }
    }

    private static func title(_ media: Selection.MediaFilter) -> String {
        switch media {
        case .all: return localizedString("Gergram.Chat.BulkDelete.AllMedia")
        case .photos: return localizedString("Gergram.Chat.BulkDelete.Photos")
        case .videos: return localizedString("Gergram.Chat.BulkDelete.Videos")
        case .voice: return localizedString("Gergram.Chat.BulkDelete.Voice")
        case .videoMessages: return localizedString("Gergram.Chat.BulkDelete.Rounds")
        case .gifs: return localizedString("Gergram.Chat.BulkDelete.Gifs")
        case .stickers: return localizedString("Gergram.Chat.BulkDelete.Stickers")
        }
    }
}
