import AlertsUI
import Foundation
import GeneralRows
import InAppSettings
import InputDataUI
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramTheme
import TelegramUtils
import TGUIKit

private enum ArchiveCaptureOption: CaseIterable {
    case deletions
    case edits
    case bots

    var key: String {
        switch self {
        case .deletions: return "CaptureDeletions"
        case .edits: return "CaptureEdits"
        case .bots: return "CaptureBots"
        }
    }

    func isEnabled(in settings: LocalArchiveCaptureSettings) -> Bool {
        switch self {
        case .deletions: return settings.captureDeletions
        case .edits: return settings.captureEdits
        case .bots: return settings.captureBots
        }
    }

    func updating(_ settings: LocalArchiveCaptureSettings, enabled: Bool) -> LocalArchiveCaptureSettings {
        LocalArchiveCaptureSettings(
            captureDeletions: self == .deletions ? enabled : settings.captureDeletions,
            captureEdits: self == .edits ? enabled : settings.captureEdits,
            captureBots: self == .bots ? enabled : settings.captureBots
        )
    }
}

private struct ArchiveEntry: Equatable {
    let id: LocalArchiveMessage.ID
    let capturedAt: Int64
    let chatTitle: String?
    let timestamp: Int32?
    let authorId: PeerId?
    let text: String?

    var stableId: String {
        let message = id.message
        return "archive-\(message.peerId.toInt64())-\(message.namespace)-\(message.id)-\(id.threadId ?? 0)-\(id.kind.rawValue)-\(id.revision)"
    }

    var kindTitle: String {
        localizedString(id.kind == .edit ? "Gergram.Archive.Edited" : "Gergram.Archive.Deleted")
    }

    func displayKindTitle(deletedMark: String) -> String {
        guard id.kind == .deletion else { return kindTitle }
        return String(format: localizedString("Gergram.Archive.DeletedKindWithMark"), kindTitle, deletedMark)
    }

    var displayChatTitle: String {
        chatTitle ?? localizedString("Gergram.Archive.UnavailableChat")
    }
}

private struct ArchivePageState: Equatable {
    var entries: [ArchiveEntry] = []
    var hasOlder = false
    var isNewest = true
    var isBusy = true
    var failed = false
}

private final class ArchiveScreenModel {
    private weak var context: (any AccountContextProtocol)?
    private let postbox: Postbox
    private let accountId: Int64
    private let scope: LocalArchiveScope
    private let operation = MetaDisposable()
    private var currentMessageRequest: MetaDisposable?
    weak var archiveController: InputDataController?
    private weak var detailController: InputDataController?
    private var page = ArchivePageState()
    private var currentCursor: LocalArchivePage.Cursor?
    private var olderCursor: LocalArchivePage.Cursor?
    let pages = ValuePromise(ArchivePageState(), ignoreRepeated: true)

    init(context: any AccountContextProtocol, scope: LocalArchiveScope) {
        self.context = context
        self.postbox = context.account.postbox
        self.accountId = context.peerId.toInt64()
        self.scope = scope
    }

    deinit {
        operation.dispose()
        currentMessageRequest?.dispose()
    }

    private var isActive: Bool {
        guard let context else { return false }
        return context.isCurrent && !context.isFrozen
            && context.account.postbox === postbox && context.peerId.toInt64() == accountId
    }

    func loadCurrent() {
        guard !page.isBusy else { return }
        load(before: currentCursor)
    }

    func loadNewest() {
        load(before: nil)
    }

    func loadOlder() {
        guard !page.isBusy, let olderCursor else { return }
        load(before: olderCursor)
    }

    func editDeletedMark() {
        guard scope == .account, let context, let archiveController,
              let navigation = activeArchiveNavigation(for: archiveController, context: context) else { return }
        navigation.push(archiveDeletedMarkController(context: context))
    }

    private func load(before cursor: LocalArchivePage.Cursor?) {
        guard isActive else { return }
        page.isBusy = true
        page.failed = false
        pages.set(page)

        let accountId = self.accountId
        let scope = self.scope
        let request = postbox.transaction { transaction -> Result<([ArchiveEntry], LocalArchivePage.Cursor?), Error> in
            Result {
                let archive = try transaction.localArchivePage(
                    accountId: accountId, scope: scope, before: cursor, limit: 40, now: Int64(Date().timeIntervalSince1970)
                )
                let entries = archive.messages.map { message in
                    let snapshot = LocalArchiveSnapshot.decode(message.snapshot)
                    return ArchiveEntry(
                        id: message.id,
                        capturedAt: message.capturedAt,
                        chatTitle: transaction.getPeer(message.id.message.peerId)?.displayTitle,
                        timestamp: snapshot?.timestamp,
                        authorId: snapshot?.authorId,
                        text: snapshot?.text
                    )
                }
                return (entries, archive.next)
            }
        }
        operation.set((request |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success((entries, next)):
                self.currentCursor = cursor
                self.olderCursor = next
                self.page = ArchivePageState(entries: entries, hasOlder: next != nil, isNewest: cursor == nil, isBusy: false)
            case .failure:
                self.currentCursor = nil
                self.olderCursor = nil
                self.page = ArchivePageState(isBusy: false, failed: true)
            }
            self.pages.set(self.page)
        }))
    }

    func updateCapture(_ option: ArchiveCaptureOption, enabled: Bool) {
        guard isActive, !page.isBusy else { return }
        _ = postbox.transaction { transaction -> Void in
            let settings = transaction.localArchiveCaptureSettings()
            transaction.updateLocalArchiveCaptureSettings(option.updating(settings, enabled: enabled))
        }.startStandalone()
    }

    func show(_ entry: ArchiveEntry) {
        guard let context, isActive, !page.isBusy, page.entries.contains(where: { $0.id == entry.id }) else { return }
        var entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(entry.displayChatTitle), data: .init(viewType: .textTopItem)),
            .desc(sectionId: 1, index: 1, text: .plain(archiveDate(entry.timestamp.map(Int64.init) ?? entry.capturedAt)), data: .init(viewType: .textTopItem)),
            .desc(sectionId: 1, index: 2, text: .plain(entry.text ?? localizedString("Gergram.Archive.UnavailableMessage")),
                  data: .init(color: theme.colors.text, detectBold: false, isTextSelectable: true, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        weak var originatingDetail: InputDataController?
        let canOpenCurrent: Bool
        if let timestamp = entry.timestamp, let authorId = entry.authorId, supportsCurrentMessage(entry.id),
           FeatureNavigationHooks.shared.makeArchivedMessageChat != nil {
            canOpenCurrent = true
            entries.append(.general(sectionId: 2, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("current-message"), data: .init(
                name: localizedString("Gergram.Archive.OpenCurrentMessage"), color: theme.colors.text, type: .next, viewType: .firstItem,
                action: { [weak self, id = entry.id] in
                    guard let originatingDetail else { return }
                    self?.openCurrentMessage(id, timestamp: timestamp, authorId: authorId, detailController: originatingDetail)
                }
            )))
        } else {
            canOpenCurrent = false
        }
        entries.append(.general(sectionId: 2, index: canOpenCurrent ? 1 : 0, value: .none, error: nil, identifier: InputDataIdentifier("remove"), data: .init(
            name: strings().contextRemove, color: theme.colors.redUI, viewType: canOpenCurrent ? .lastItem : .singleItem, action: { [weak self, id = entry.id] in
                self?.confirmRemove(id)
            }
        )))
        var scopes: [(LocalArchiveScope, String)] = []
        if scope == .account {
            scopes.append((.chat(entry.id.message.peerId), "Gergram.Archive.Chat"))
        }
        if let threadId = entry.id.threadId, scope != .thread(entry.id.message.peerId, threadId) {
            scopes.append((.thread(entry.id.message.peerId, threadId), "Gergram.Archive.Topic"))
        }
        if !scopes.isEmpty {
            entries.append(.sectionId(2, type: .normal))
            for (index, item) in scopes.enumerated() {
                let (nextScope, key) = item
                entries.append(.general(sectionId: 3, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier(key), data: .init(
                    name: localizedString(key), color: theme.colors.text, type: .next, viewType: bestGeneralViewType(scopes, for: index), action: { [weak self] in
                        guard let self, let context = self.context, self.isActive, !self.page.isBusy else { return }
                        context.bindings.rootNavigation().push(localMessageArchiveController(context: context, scope: nextScope, titleKey: key))
                    }
                )))
            }
        }
        let detail = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: entry.displayKindTitle(deletedMark: ArchiveDeletedMarkPreferences.shared.mark), hasDone: false)
        originatingDetail = detail
        self.detailController = detail
        detail.willDisappear = { [weak self] detail in
            guard let self, self.detailController === detail else { return }
            let request = self.currentMessageRequest
            self.currentMessageRequest = nil
            request?.dispose()
        }
        context.bindings.rootNavigation().push(detail)
    }

    private func supportsCurrentMessage(_ id: LocalArchiveMessage.ID) -> Bool {
        let messageId = id.message
        guard id.kind == .edit, messageId.namespace == Namespaces.Message.Cloud, messageId.id > 0,
              messageId.peerId.id._internalGetInt64Value() > 0, messageId.peerId.toInt64() != accountId else {
            return false
        }
        switch scope {
        case .account:
            return true
        case let .chat(peerId):
            return peerId == messageId.peerId
        case let .thread(peerId, threadId):
            return peerId == messageId.peerId && threadId == id.threadId
        }
    }

    private func openCurrentMessage(_ id: LocalArchiveMessage.ID, timestamp: Int32, authorId: PeerId, detailController: InputDataController) {
        guard currentMessageRequest == nil, let context,
              currentMessageNavigation(id, timestamp: timestamp, authorId: authorId, detail: detailController) != nil,
              supportsCurrentMessage(id) else { return }

        let request = MetaDisposable()
        currentMessageRequest = request
        let contentSettings = context.contentSettings
        let lookup = postbox.transaction { transaction in
            currentArchiveMessageLocation(id, timestamp: timestamp, authorId: authorId, contentSettings: contentSettings, transaction: transaction)
        }
        request.set((lookup |> deliverOnMainQueue).start(next: { [weak self, weak detailController, weak request] location in
            guard let self, let request, self.currentMessageRequest === request else { return }
            self.currentMessageRequest = nil
            request.dispose()
            guard let context = self.context, context.contentSettings == contentSettings, let detailController,
                  let navigation = self.currentMessageNavigation(id, timestamp: timestamp, authorId: authorId, detail: detailController) else { return }
            guard let location,
                  let chat = FeatureNavigationHooks.shared.makeArchivedMessageChat?(context, location, id.message) else {
                self.showCurrentMessageUnavailable(context)
                return
            }
            let presentation = MetaDisposable()
            self.currentMessageRequest = presentation
            chat.navigationController = navigation
            let ready = chat.ready.get() |> filter { $0 } |> take(1)
                |> timeout(15, queue: .mainQueue(), alternate: .single(false)) |> deliverOnMainQueue
            presentation.set(ready.start(next: { [weak self, weak detailController, weak navigation, weak presentation] ready in
                guard let self, let presentation, self.currentMessageRequest === presentation else { return }
                self.currentMessageRequest = nil
                presentation.dispose()
                guard let context = self.context, context.contentSettings == contentSettings, let detailController, let navigation,
                      self.currentMessageNavigation(id, timestamp: timestamp, authorId: authorId, detail: detailController) === navigation else { return }
                guard ready else {
                    self.showCurrentMessageUnavailable(context)
                    return
                }
                navigation.push(chat)
            }))
            if self.currentMessageRequest === presentation {
                chat.loadViewIfNeeded(navigation.bounds)
            }
        }))
    }

    private func currentMessageNavigation(_ id: LocalArchiveMessage.ID, timestamp: Int32, authorId: PeerId, detail: InputDataController) -> NavigationViewController? {
        guard let context, isActive, !page.isBusy, detailController === detail,
              page.entries.contains(where: { $0.id == id && $0.timestamp == timestamp && $0.authorId == authorId }) else { return nil }
        return activeArchiveNavigation(for: detail, context: context)
    }

    private func showCurrentMessageUnavailable(_ context: any AccountContextProtocol) {
        alert(for: context.window, header: localizedString("Gergram.Archive.OpenCurrentMessage"), info: localizedString("Gergram.Archive.CurrentMessageUnavailable"))
    }

    private func confirmRemove(_ id: LocalArchiveMessage.ID) {
        guard let context, isActive, !page.isBusy else { return }
        verifyAlert_button(for: context.window, header: localizedString("Gergram.Archive.RemoveMessage"),
                           information: localizedString("Gergram.Archive.RemoveMessageDescription"), ok: strings().contextRemove, successHandler: { [weak self] _ in
            self?.remove(id)
        })
    }

    private func remove(_ id: LocalArchiveMessage.ID) {
        guard isActive, !page.isBusy else { return }
        page.isBusy = true
        pages.set(page)
        let accountId = self.accountId
        let request = postbox.transaction { transaction -> Result<Bool, Error> in
            Result { try transaction.removeLocalArchiveMessage(accountId: accountId, id: id) }
        }
        operation.set((request |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else { return }
            self.page.isBusy = false
            self.pages.set(self.page)
            guard let context = self.context, self.isActive else { return }
            switch result {
            case .success:
                self.loadNewest()
                let navigation = context.bindings.rootNavigation()
                if let detail = self.detailController, navigation.controller === detail {
                    navigation.back()
                }
            case .failure:
                alert(for: context.window, header: localizedString("Gergram.Archive.Title"), info: localizedString("Gergram.Archive.Error"))
            }
        }))
    }

    func confirmClear() {
        guard let context, isActive, !page.isBusy else { return }
        let description = scope == .account ? "Gergram.Archive.ClearDescription" : "Gergram.Archive.ClearScopeDescription"
        verifyAlert_button(for: context.window, header: localizedString("Gergram.Archive.Clear"),
                           information: localizedString(description), ok: localizedString("Gergram.Archive.Clear"), successHandler: { [weak self] _ in
            self?.clear()
        })
    }

    private func clear() {
        guard isActive, !page.isBusy else { return }
        page = ArchivePageState()
        pages.set(page)
        let accountId = self.accountId
        let scope = self.scope
        let request = postbox.transaction { transaction -> Result<Void, Error> in
            Result {
                if scope == .account {
                    transaction.updateLocalArchiveCaptureSettings(.defaultSettings)
                }
                for _ in 0 ..< 33 {
                    if try !transaction.clearLocalArchive(accountId: accountId, scope: scope, limit: 128) {
                        return
                    }
                }
                throw LocalArchiveError.invalidLimit
            }
        }
        _ = (request |> deliverOnMainQueue).startStandalone(next: { [weak self] result in
            guard let self else { return }
            self.page.isBusy = false
            self.pages.set(self.page)
            guard let context = self.context, self.isActive else { return }
            if case .failure = result {
                alert(for: context.window, header: localizedString("Gergram.Archive.Title"), info: localizedString("Gergram.Archive.Error"))
            }
            self.loadNewest()
        })
    }
}

private func currentArchiveMessageLocation(
    _ id: LocalArchiveMessage.ID, timestamp: Int32, authorId: PeerId,
    contentSettings: ContentSettings, transaction: Transaction
) -> ChatLocation? {
    let messageId = id.message
    guard let peer = transaction.getPeer(messageId.peerId), peer.id == messageId.peerId,
          !peer.isCopyProtectionEnabled, !peer.isMonoForum,
          peer.restrictionText(platform: "ios", contentSettings: contentSettings) == nil,
          !peer.hasSensitiveContent(platform: "ios", contentSettings: contentSettings),
          let current = transaction.getMessage(messageId), current.id == messageId,
          current.threadId == id.threadId, current.timestamp == timestamp, current.author?.id == authorId,
          current.flags.contains(.Incoming), current.forwardInfo == nil, !current.isCopyProtected(),
          !current.attributes.contains(where: {
              $0 is AutoclearTimeoutMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute
                  || $0 is EphemeralMessageAttribute || $0 is EphemeralOutgoingMessageAttribute
                  || $0 is EphemeralReplacementMessageAttribute || $0 is RestrictedContentMessageAttribute
          }) else { return nil }

    switch peer {
    case let user as TelegramUser:
        guard !user.isDeleted, !peer.isForumOrMonoForum,
              let cached = transaction.getPeerCachedData(peerId: messageId.peerId) as? CachedUserData,
              cached.flags.intersection([.copyProtectionEnabled, .myCopyProtectionEnabled]).isEmpty else { return nil }
    case let group as TelegramGroup:
        guard group.membership == .Member, group.migrationReference == nil else { return nil }
    case let channel as TelegramChannel:
        guard channel.participationStatus == .member else { return nil }
    default:
        return nil
    }

    guard let threadId = id.threadId else {
        return peer.isForumOrMonoForum ? nil : .peer(messageId.peerId)
    }
    guard peer.isForumOrMonoForum, threadId > 0, let rootId = Int32(exactly: threadId),
          let topic = transaction.getMessageHistoryThreadInfo(peerId: messageId.peerId, threadId: threadId)?.data.get(MessageHistoryThreadData.self),
          !topic.isHidden, messageId.id != rootId else { return nil }
    func topicPosition(_ value: Int32) -> MessageId? {
        value > 0 ? MessageId(peerId: messageId.peerId, namespace: messageId.namespace, id: value) : nil
    }
    return .thread(ChatReplyThreadMessage(
        peerId: messageId.peerId, threadId: threadId, channelMessageId: nil, isChannelPost: false,
        isForumPost: true, isMonoforumPost: false, maxMessage: topicPosition(topic.maxKnownMessageId),
        maxReadIncomingMessageId: topicPosition(topic.maxIncomingReadId), maxReadOutgoingMessageId: topicPosition(topic.maxOutgoingReadId),
        unreadCount: Int(max(0, topic.incomingUnreadCount)), initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false
    ))
}

private func activeArchiveNavigation(
    for controller: InputDataController, context: any AccountContextProtocol
) -> NavigationViewController? {
    guard context.isCurrent, !context.isFrozen, let navigation = controller.navigationController,
          navigation.controller === controller, controller.window === context.window,
          context.window.isVisible, !hasModals(context.window) else { return nil }
    return navigation
}

private func archiveDeletedMarkController(
    context: any AccountContextProtocol, preferences: ArchiveDeletedMarkPreferences = .shared
) -> InputDataController {
    let identifier = InputDataIdentifier("deleted-mark-text")
    let title = localizedString("Gergram.Archive.DeletedMark")
    let mark = preferences.mark
    let entries: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .input(sectionId: 1, index: 0, value: .string(mark == ArchiveDeletedMarkPreferences.defaultMark ? "" : mark), error: nil,
               identifier: identifier, mode: .plain, data: .init(viewType: .singleItem),
               placeholder: nil, inputPlaceholder: ArchiveDeletedMarkPreferences.defaultMark, filter: { $0 },
               limit: Int32(ArchiveDeletedMarkPreferences.maximumCustomTextUTF16Length)),
        .desc(sectionId: 1, index: 1, text: .plain(localizedString("Gergram.Archive.DeletedMarkHelp")),
              data: .init(viewType: .textBottomItem))
    ]
    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: title)
    controller.validateData = { [weak controller, weak context] data in
        guard let controller, let context, activeArchiveNavigation(for: controller, context: context) != nil,
              let value = data[identifier]?.stringValue else { return .none }
        guard preferences.setCustomMark(value) else {
            return .fail(.alert(localizedString("Gergram.Archive.InvalidDeletedMark")))
        }
        return .success(.navigationBack)
    }
    return controller
}

private func archiveDate(_ timestamp: Int64) -> String {
    DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(timestamp)), dateStyle: .medium, timeStyle: .short)
}

public func localMessageArchiveController(context: any AccountContextProtocol, location: ChatLocation) -> InputDataController {
    if let threadId = location.threadId, threadId > 0 {
        return localMessageArchiveController(context: context, scope: .thread(location.peerId, threadId), titleKey: "Gergram.Archive.Topic")
    }
    return localMessageArchiveController(context: context, scope: .chat(location.peerId), titleKey: "Gergram.Archive.Chat")
}

func localMessageArchiveController(
    context: any AccountContextProtocol, scope: LocalArchiveScope = .account, titleKey: String = "Gergram.Archive.Title"
) -> InputDataController {
    let model = ArchiveScreenModel(context: context, scope: scope)
    let preferences: Signal<LocalArchiveCaptureSettings, NoError>
    if scope == .account {
        preferences = context.account.postbox.preferencesView(keys: [LocalArchiveCaptureSettings.key])
        |> map { $0.values[LocalArchiveCaptureSettings.key]?.get(LocalArchiveCaptureSettings.self) ?? .defaultSettings }
        |> distinctUntilChanged
    } else {
        preferences = .single(.defaultSettings)
    }
    let signal = combineLatest(preferences, model.pages.get(), ArchiveDeletedMarkPreferences.shared.signal)
    |> map { [weak model] settings, page, deletedMark -> InputDataSignalValue in
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        if scope == .account {
            let options = ArchiveCaptureOption.allCases
            for (index, option) in options.enumerated() {
                let enabled = option.isEnabled(in: settings)
                entries.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier(option.key), data: .init(
                    name: localizedString("Gergram.Archive.\(option.key)"), color: theme.colors.text, type: .switchable(enabled),
                    viewType: bestGeneralViewType(options, for: index), enabled: !page.isBusy, action: { [weak model] in
                        model?.updateCapture(option, enabled: !enabled)
                    }, autoswitch: false
                )))
            }
            entries.append(.desc(sectionId: 1, index: 3, text: .plain(localizedString("Gergram.Archive.Description")), data: .init(viewType: .textBottomItem)))
            entries.append(.general(sectionId: 1, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("deleted-mark"), data: .init(
                name: localizedString("Gergram.Archive.DeletedMark"), color: theme.colors.text, type: .nextContext(deletedMark),
                viewType: .singleItem, action: { [weak model] in model?.editDeletedMark() }
            )))
        }
        entries.append(.sectionId(1, type: .normal))

        for (index, entry) in page.entries.enumerated() {
            let label = String(format: localizedString("Gergram.Archive.Row"), entry.displayKindTitle(deletedMark: deletedMark), entry.displayChatTitle)
            entries.append(.general(sectionId: 2, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier(entry.stableId), data: .init(
                name: label, color: theme.colors.text, type: .next, viewType: bestGeneralViewType(page.entries, for: index), enabled: !page.isBusy,
                description: archiveDate(entry.capturedAt), action: { [weak model] in model?.show(entry) }
            )))
        }
        if page.entries.isEmpty {
            let key = page.isBusy ? "Loading" : (page.failed ? "Error" : "Empty")
            entries.append(.desc(sectionId: 2, index: 0, text: .plain(localizedString("Gergram.Archive.\(key)")), data: .init(viewType: .textTopItem)))
        }
        entries.append(.sectionId(2, type: .normal))

        if page.hasOlder {
            entries.append(.general(sectionId: 3, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("older"), data: .init(
                name: localizedString("Gergram.Archive.Older"), color: theme.colors.accent, viewType: .singleItem,
                enabled: !page.isBusy, action: { [weak model] in model?.loadOlder() }
            )))
        }
        entries.append(.general(sectionId: 3, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("refresh"), data: .init(
            name: localizedString(page.isNewest ? "Gergram.Archive.Refresh" : "Gergram.Archive.Newest"), color: theme.colors.accent,
            viewType: .singleItem, enabled: !page.isBusy, action: { [weak model] in model?.loadNewest() }
        )))
        entries.append(.sectionId(3, type: .normal))
        entries.append(.general(sectionId: 4, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("clear"), data: .init(
            name: localizedString("Gergram.Archive.Clear"), color: theme.colors.redUI, viewType: .singleItem,
            enabled: !page.isBusy, action: { [weak model] in model?.confirmClear() }
        )))
        return InputDataSignalValue(entries: entries)
    }
    let controller = InputDataController(dataSignal: signal, title: localizedString(titleKey), removeAfterDisappear: false, hasDone: false)
    model.archiveController = controller
    controller.contextObject = model
    controller.didAppear = { [weak model] _ in model?.loadCurrent() }
    model.loadNewest()
    return controller
}
