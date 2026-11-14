import AlertsUI
import AppKit
import Darwin
import FilePanels
import InAppSettings
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
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

    static func copySharedRulesLink(context: any AccountContextProtocol) {
        let window = context.window
        guard isTransferCurrent(context, window: window) else { return }
        _ = (localMessageFilterPreferences(context.account.postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak context, weak window] preferences in
            guard let context, let window, isTransferCurrent(context, window: window) else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak context, weak window] in
                let result = Result { try LocalMessageFilterTransfer.encodeSharedRulesLink(preferences) }
                DispatchQueue.main.async {
                    guard let context, let window, isTransferCurrent(context, window: window) else { return }
                    switch result {
                    case let .success(link):
                        copyToClipboard(link)
                        showModalText(for: window, text: localizedString("Gergram.Chat.FilterTransferLinkCopied"))
                    case let .failure(error):
                        showError(error, window: window)
                    }
                }
            }
        })
    }

    static func importSharedRulesLink(context: any AccountContextProtocol) {
        let window = context.window
        guard isTransferCurrent(context, window: window) else { return }
        guard let link = NSPasteboard.general.string(forType: .string) else {
            showError(LocalMessageFilterTransfer.Error.invalidLink, window: window)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak context, weak window] in
            let result = Result { try LocalMessageFilterTransfer.decodeSharedRulesLink(link) }
            DispatchQueue.main.async {
                guard let context, let window, isTransferCurrent(context, window: window) else { return }
                switch result {
                case let .success(backup):
                    preview(.sharedRules(backup), context: context, window: window, showsRuleDetails: true)
                case let .failure(error):
                    showError(error, window: window)
                }
            }
        }
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

    private static func preview(_ imported: LocalMessageFilterTransfer.Import, context: any AccountContextProtocol, window: Window, showsRuleDetails: Bool = false) {
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
            let apply = { [weak context, weak window] in
                guard let context, let window, isTransferCurrent(context, window: window) else { return }
                let update = updateLocalMessageFilterPreferences(postbox) { current -> Bool in
                    guard current == previous else { return false }
                    current = updated
                    return true
                }
                _ = (update |> deliverOnMainQueue).startStandalone(next: { [weak context, weak window] applied in
                    guard !applied, let context, let window, isTransferCurrent(context, window: window) else { return }
                    let key = showsRuleDetails ? "Gergram.Chat.FilterTransferLinkStale" : "Gergram.Chat.FilterTransferStale"
                    alert(for: window, header: title, info: localizedString(key))
                })
            }
            if showsRuleDetails, case let .sharedRules(backup) = imported {
                confirmSharedRulesLink(backup.rules, context: context, window: window, title: title, description: description, confirmTitle: confirmTitle, apply: apply)
            } else {
                verifyAlert(for: window, header: title, information: description, ok: confirmTitle, successHandler: { _ in apply() })
            }
        })
    }

    private static func confirmSharedRulesLink(_ rules: [LocalMessageFilterRule], context: any AccountContextProtocol, window: Window, title: String, description: String, confirmTitle: String, apply: @escaping () -> Void) {
        guard window.attachedSheet == nil else { return }
        let id = String(context.peerId.id._internalGetInt64Value())
        let account = context.myPeer.map { "\(visibleText($0.displayTitle)) (\(id))" } ?? id
        let accountDescription = String(format: localizedString("Gergram.Chat.FilterTransferLinkAccount"), account)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = description + "\n\n" + accountDescription
        let cancelButton = alert.addButton(withTitle: strings().alertCancel)
        cancelButton.keyEquivalent = "\u{1b}"
        let importButton = alert.addButton(withTitle: confirmTitle)
        importButton.keyEquivalent = ""

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        text.string = rules.map { rule in
            let enabled = localizedString(rule.isEnabled ? "Gergram.Chat.FilterRuleEnabled" : "Gergram.Chat.FilterRuleDisabled")
            let matchCase = localizedString(rule.isCaseInsensitive ? "Gergram.Chat.FilterCaseInsensitive" : "Gergram.Chat.FilterTransferLinkMatchCase")
            let matches = localizedString(rule.isReversed ? "Gergram.Chat.FilterReversed" : "Gergram.Chat.FilterTransferLinkHideMatching")
            return visibleText(rule.pattern) + "\n" + [enabled, matchCase, matches].joined(separator: " · ")
        }.joined(separator: "\n\n")
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { apply() }
        }
    }

    private static func visibleText(_ value: String) -> String {
        var text = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5c: text += "\\\\"
            case 0x09: text += "\\t"
            case 0x0a: text += "\\n"
            case 0x0d: text += "\\r"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator: text += "\\u{\(String(scalar.value, radix: 16))}"
                default: text.unicodeScalars.append(scalar)
                }
            }
        }
        return text
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
        case .invalidLink:
            message = "Gergram.Chat.FilterTransferInvalidLink"
        case .linkTooLarge:
            message = "Gergram.Chat.FilterTransferLinkTooLarge"
        case .invalidFile, nil:
            message = "Gergram.Chat.FilterTransferFailed"
        }
        alert(for: window, info: localizedString(message))
    }
}
