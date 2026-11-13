import AlertsUI
import Foundation
import GeneralRows
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
    let text: String?

    var stableId: String {
        let message = id.message
        return "archive-\(message.peerId.toInt64())-\(message.namespace)-\(message.id)-\(id.threadId ?? 0)-\(id.kind.rawValue)-\(id.revision)"
    }

    var kindTitle: String {
        localizedString(id.kind == .edit ? "Gergram.Archive.Edited" : "Gergram.Archive.Deleted")
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
    }

    private var isActive: Bool {
        guard let context else { return false }
        return context.isCurrent && !context.isFrozen
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
        entries.append(.general(sectionId: 2, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("remove"), data: .init(
            name: strings().contextRemove, color: theme.colors.redUI, viewType: .singleItem, action: { [weak self, id = entry.id] in
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
        let detail = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: entry.kindTitle, hasDone: false)
        self.detailController = detail
        context.bindings.rootNavigation().push(detail)
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
        verifyAlert_button(for: context.window, header: localizedString("Gergram.Archive.Clear"),
                           information: localizedString("Gergram.Archive.ClearDescription"), ok: localizedString("Gergram.Archive.Clear"), successHandler: { [weak self] _ in
            self?.clear()
        })
    }

    private func clear() {
        guard isActive, !page.isBusy else { return }
        page = ArchivePageState()
        pages.set(page)
        let accountId = self.accountId
        let request = postbox.transaction { transaction -> Result<Void, Error> in
            Result {
                transaction.updateLocalArchiveCaptureSettings(.defaultSettings)
                for _ in 0 ..< 33 {
                    if try !transaction.clearLocalArchive(accountId: accountId, scope: .account, limit: 128) {
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

private func archiveDate(_ timestamp: Int64) -> String {
    DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(timestamp)), dateStyle: .medium, timeStyle: .short)
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
    let signal = combineLatest(preferences, model.pages.get()) |> map { [weak model] settings, page -> InputDataSignalValue in
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
        }
        entries.append(.sectionId(1, type: .normal))

        for (index, entry) in page.entries.enumerated() {
            let label = String(format: localizedString("Gergram.Archive.Row"), entry.kindTitle, entry.displayChatTitle)
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
        if scope == .account {
            entries.append(.sectionId(3, type: .normal))
            entries.append(.general(sectionId: 4, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("clear"), data: .init(
                name: localizedString("Gergram.Archive.Clear"), color: theme.colors.redUI, viewType: .singleItem,
                enabled: !page.isBusy, action: { [weak model] in model?.confirmClear() }
            )))
        }
        return InputDataSignalValue(entries: entries)
    }
    let controller = InputDataController(dataSignal: signal, title: localizedString(titleKey), removeAfterDisappear: false, hasDone: false)
    controller.contextObject = model
    controller.didAppear = { [weak model] _ in model?.loadCurrent() }
    model.loadNewest()
    return controller
}
