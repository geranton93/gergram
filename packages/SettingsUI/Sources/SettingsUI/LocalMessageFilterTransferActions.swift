import AlertsUI
import AppKit
import Darwin
import FilePanels
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramContext
import TGUIKit
import UniformTypeIdentifiers

enum LocalMessageFilterTransferActions {
    static func importRules(context: any AccountContextProtocol) {
        guard (context.isCurrent || context.isExternal), !context.isFrozen else { return }
        let window = context.window
        let accountPeerId = context.peerId
        filePanel(with: ["json"], allowMultiple: false, for: window) { [weak context, weak window] files in
            guard let path = files?.first, let context, let window, isTransferCurrent(context, window: window) else { return }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.global(qos: .userInitiated).async { [weak context, weak window] in
                let result = Result { try readRules(from: url, accountPeerId: accountPeerId) }
                DispatchQueue.main.async {
                    guard let context, let window, isTransferCurrent(context, window: window) else { return }
                    switch result {
                    case let .success(imported):
                        preview(imported, context: context, window: window)
                    case let .failure(error):
                        showError(error, window: window)
                    }
                }
            }
        }
    }

    static func exportRules(context: any AccountContextProtocol, sharedOnly: Bool = false) {
        let window = context.window
        guard isTransferCurrent(context, window: window) else { return }
        let accountPeerId = context.peerId
        _ = (localMessageFilterPreferences(context.account.postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak context, weak window] preferences in
            guard let context, let window, isTransferCurrent(context, window: window) else { return }
            if sharedOnly, !preferences.rules.contains(where: { $0.chatId == nil }) {
                showError(LocalMessageFilterTransfer.Error.noSharedRules, window: window)
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = sharedOnly ? "gergram-shared-message-filters.json" : "gergram-message-filters.json"
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = [.json]
            } else {
                panel.allowedFileTypes = ["json"]
            }
            panel.beginSheetModal(for: window) { [weak context, weak window] response in
                guard response == .OK, let url = panel.url, let context, let window, isTransferCurrent(context, window: window) else { return }
                DispatchQueue.global(qos: .userInitiated).async { [weak context, weak window] in
                    do {
                        let data = sharedOnly ? try LocalMessageFilterTransfer.encodeSharedRules(preferences)
                            : try LocalMessageFilterTransfer.encode(preferences, accountPeerId: accountPeerId)
                        try data.write(to: url, options: .atomic)
                    } catch {
                        DispatchQueue.main.async {
                            guard let context, let window, isTransferCurrent(context, window: window) else { return }
                            showError(error, window: window)
                        }
                    }
                }
            }
        })
    }

    private static func readRules(from url: URL, accountPeerId: PeerId) throws -> LocalMessageFilterTransfer.Import {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_CLOEXEC | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw LocalMessageFilterTransfer.Error.invalidFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { handle.closeFile() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw LocalMessageFilterTransfer.Error.invalidFile
        }
        let maximumBytes = LocalMessageFilterTransfer.maximumBytes
        guard metadata.st_size <= maximumBytes else { throw LocalMessageFilterTransfer.Error.fileTooLarge }
        var data = Data()
        while data.count <= maximumBytes {
            let count = min(64 * 1024, maximumBytes - data.count + 1)
            let chunk: Data
            if #available(macOS 10.15.4, *) {
                chunk = try handle.read(upToCount: count) ?? Data()
            } else {
                chunk = handle.readData(ofLength: count)
            }
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return try LocalMessageFilterTransfer.decodeImport(data, accountPeerId: accountPeerId)
    }

    private static func isTransferCurrent(_ context: any AccountContextProtocol, window: Window) -> Bool {
        context.window === window && window.isVisible && (context.isCurrent || context.isExternal) && !context.isFrozen
    }

    private static func preview(_ imported: LocalMessageFilterTransfer.Import, context: any AccountContextProtocol, window: Window) {
        let postbox = context.account.postbox
        _ = (localMessageFilterPreferences(postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak context, weak window] previous in
            guard let context, let window, isTransferCurrent(context, window: window) else { return }
            let updated: LocalMessageFilterPreferences
            let description: String
            let confirmTitle: String
            let title = localizedString("Gergram.Chat.FilterTransferImport")
            switch imported {
            case let .replacement(preferences):
                updated = preferences
                let scopedCount = preferences.rules.filter { $0.chatId != nil }.count
                description = String(format: localizedString("Gergram.Chat.FilterTransferPreview"), String(preferences.rules.count), String(scopedCount), String(previous.rules.count))
                confirmTitle = localizedString("Gergram.Chat.FilterTransferReplace")
            case let .sharedRules(backup):
                do {
                    let merge = try backup.merging(into: previous)
                    guard merge.added > 0 || merge.updated > 0 else {
                        alert(for: window, header: title, info: localizedString("Gergram.Chat.FilterTransferNoChanges"))
                        return
                    }
                    updated = merge.preferences
                    description = String(format: localizedString("Gergram.Chat.FilterTransferSharedPreview"), String(backup.rules.count), String(merge.added), String(merge.updated))
                    confirmTitle = localizedString("Gergram.Chat.FilterTransferMerge")
                } catch {
                    showError(error, window: window)
                    return
                }
            }
            verifyAlert(for: window, header: title, information: description, ok: confirmTitle, successHandler: { [weak context, weak window] _ in
                guard let context, let window, isTransferCurrent(context, window: window) else { return }
                let update = updateLocalMessageFilterPreferences(postbox) { current -> Bool in
                    guard current == previous else { return false }
                    current = updated
                    return true
                }
                _ = (update |> deliverOnMainQueue).startStandalone(next: { [weak context, weak window] applied in
                    guard !applied, let context, let window, isTransferCurrent(context, window: window) else { return }
                    alert(for: window, header: localizedString("Gergram.Chat.FilterTransferImport"), info: localizedString("Gergram.Chat.FilterTransferStale"))
                })
            })
        })
    }

    private static func showError(_ error: Swift.Error, window: Window) {
        let message: String
        switch error as? LocalMessageFilterTransfer.Error {
        case .fileTooLarge:
            message = "Gergram.Chat.FilterTransferTooLarge"
        case .unsupportedVersion:
            message = "Gergram.Chat.FilterTransferUnsupported"
        case .differentAccount:
            message = "Gergram.Chat.FilterTransferDifferentAccount"
        case .unsupportedSharedBackup:
            message = "Gergram.Chat.FilterTransferUnsupportedSharedBackup"
        case .sharedRuleCollision:
            message = "Gergram.Chat.FilterTransferSharedRuleCollision"
        case .tooManyRules:
            message = "Gergram.Chat.FilterTransferTooManyRules"
        case .noSharedRules:
            message = "Gergram.Chat.FilterTransferNoSharedRules"
        case .invalidFile, nil:
            message = "Gergram.Chat.FilterTransferFailed"
        }
        alert(for: window, info: localizedString(message))
    }
}
