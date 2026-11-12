import AlertsUI
import AppKit
import FilePanels
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramContext
import TGUIKit
import UniformTypeIdentifiers

enum LocalMessageFilterTransferActions {
    static func importRules(context: any AccountContextProtocol) {
        guard !context.isFrozen else { return }
        let window = context.window
        let accountPeerId = context.peerId
        filePanel(with: ["json"], allowMultiple: false, for: window) { [weak window] files in
            guard let path = files?.first else { return }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try readRules(from: url, accountPeerId: accountPeerId) }
                DispatchQueue.main.async {
                    guard let window, window.isVisible, !context.isFrozen else { return }
                    switch result {
                    case let .success(preferences):
                        preview(preferences, context: context, window: window)
                    case let .failure(error):
                        showError(error, window: window)
                    }
                }
            }
        }
    }

    static func exportRules(context: any AccountContextProtocol) {
        let window = context.window
        let accountPeerId = context.peerId
        _ = (localMessageFilterPreferences(context.account.postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak window] preferences in
            guard let window, window.isVisible else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "gergram-message-filters.json"
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = [.json]
            } else {
                panel.allowedFileTypes = ["json"]
            }
            panel.beginSheetModal(for: window) { [weak window] response in
                guard response == .OK, let url = panel.url else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try LocalMessageFilterTransfer.encode(preferences, accountPeerId: accountPeerId)
                        try data.write(to: url, options: .atomic)
                    } catch {
                        DispatchQueue.main.async {
                            if let window, window.isVisible {
                                showError(error, window: window)
                            }
                        }
                    }
                }
            }
        })
    }

    private static func readRules(from url: URL, accountPeerId: PeerId) throws -> LocalMessageFilterPreferences {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw LocalMessageFilterTransfer.Error.invalidFile }
        if let size = values.fileSize, size > LocalMessageFilterTransfer.maximumBytes {
            throw LocalMessageFilterTransfer.Error.fileTooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let length = LocalMessageFilterTransfer.maximumBytes + 1
        let data: Data
        if #available(macOS 10.15.4, *) {
            data = try handle.read(upToCount: length) ?? Data()
        } else {
            data = handle.readData(ofLength: length)
        }
        return try LocalMessageFilterTransfer.decode(data, accountPeerId: accountPeerId)
    }

    private static func preview(_ imported: LocalMessageFilterPreferences, context: any AccountContextProtocol, window: Window) {
        let postbox = context.account.postbox
        _ = (localMessageFilterPreferences(postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak window] previous in
            guard let window, window.isVisible else { return }
            let scopedCount = imported.rules.filter { $0.chatId != nil }.count
            let description = String(format: localizedString("Gergram.Chat.FilterTransferPreview"), String(imported.rules.count), String(scopedCount), String(previous.rules.count))
            verifyAlert(for: window, header: localizedString("Gergram.Chat.FilterTransferImport"), information: description, ok: localizedString("Gergram.Chat.FilterTransferReplace"), successHandler: { [weak window] _ in
                guard let window, window.isVisible, !context.isFrozen else { return }
                let update = updateLocalMessageFilterPreferences(postbox) { current -> Bool in
                    guard current == previous else { return false }
                    current = imported
                    return true
                }
                _ = (update |> deliverOnMainQueue).startStandalone(next: { [weak window] applied in
                    guard !applied, let window, window.isVisible else { return }
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
        case .invalidFile, nil:
            message = "Gergram.Chat.FilterTransferFailed"
        }
        alert(for: window, info: localizedString(message))
    }
}
