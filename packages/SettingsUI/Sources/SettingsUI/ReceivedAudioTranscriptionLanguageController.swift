import AppKit
import GeneralRows
import InAppSettings
import InputDataUI
import KeyboardKey
import Localization
import SwiftSignalKit
import TelegramTheme
import TGUIKit

private typealias TranscriptionLanguage = ReceivedAudioTranscriptionLanguagePreferences

private final class TranscriptionLanguageKeyboardNavigation: TableViewDelegate {
    weak var table: TableView?
    let search = ValuePromise("", ignoreRepeated: true)
    private var query = ""

    func updateSearch(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        table?.cancelSelection()
        search.set(query)
    }

    func isSelectable(row: Int, item: TableRowItem) -> Bool {
        guard let item = item as? GeneralInteractedRowItem, item.enabled,
              case let .general(identifier)? = item.stableId.base as? InputDataEntryId else { return false }
        if identifier == transcriptionAutomaticIdentifier {
            return true
        }
        guard identifier.identifier.hasPrefix(transcriptionLocalePrefix) else { return false }
        let locale = Locale(identifier: String(identifier.identifier.dropFirst(transcriptionLocalePrefix.count)))
        return transcriptionLanguageMatches(locale, query: query)
    }

    func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return !byClick && isSelectable(row: row, item: item)
    }

    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {}

    func move(in table: TableView, forward: Bool) -> KeyHandlerResult {
        if let item = table.selectedItem(), isSelectable(row: item.index, item: item) {
            if forward {
                table.selectNext(turnDirection: false)
            } else {
                table.selectPrev(turnDirection: false)
            }
        } else {
            table.cancelSelection()
            table.selectNext(turnDirection: false)
        }
        return table.selectedItem() != nil ? .invoked : .rejected
    }

    func activate(in table: TableView) -> Bool {
        guard let item = table.selectedItem() as? GeneralInteractedRowItem, isSelectable(row: item.index, item: item) else { return false }
        item.action()
        return true
    }
}

private let transcriptionAutomaticIdentifier = InputDataIdentifier("transcription-language-automatic")
private let transcriptionLocalePrefix = "transcription-language-locale-"

private func transcriptionLanguageMatches(_ locale: Locale, query: String) -> Bool {
    return query.isEmpty || TranscriptionLanguage.displayName(for: locale).localizedStandardContains(query)
        || locale.localizedString(forIdentifier: locale.identifier)?.localizedStandardContains(query) == true
        || locale.identifier.localizedStandardContains(query)
}

func receivedAudioTranscriptionLanguageTitle(_ selection: ReceivedAudioTranscriptionLanguagePreferences.Selection) -> String {
    switch selection {
    case .automatic:
        return localizedString("Gergram.Transcription.Language.Automatic")
    case let .locale(identifier):
        return TranscriptionLanguage.displayName(for: Locale(identifier: identifier))
    }
}

func receivedAudioTranscriptionLanguageController() -> InputDataController {
    let preferences = TranscriptionLanguage.shared
    let navigation = TranscriptionLanguageKeyboardNavigation()
    let discovery = Signal<[Locale]?, NoError> { subscriber in
        subscriber.putNext(TranscriptionLanguage.availableLocales())
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(.concurrentDefaultQueue())
    let locales: Signal<[Locale]?, NoError> = .single(nil) |> then(discovery)

    let signal = combineLatest(queue: prepareQueue, preferences.signal, locales, navigation.search.get(), appearanceSignal)
    |> map { [weak navigation] selection, locales, query, appearance in
        var section: Int32 = 1
        let colors = appearance.presentation.colors
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        func addChoice(_ choice: TranscriptionLanguage.Selection, title: String, viewType: GeneralViewType, enabled: Bool = true) {
            let id: InputDataIdentifier
            switch choice {
            case .automatic: id = transcriptionAutomaticIdentifier
            case let .locale(identifier): id = .init(transcriptionLocalePrefix + identifier)
            }
            let selected: Bool
            if case let .locale(current) = selection, case let .locale(candidate) = choice {
                selected = TranscriptionLanguage.localeIdentifierMatches(current, candidate)
            } else {
                selected = selection == choice
            }
            entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: id,
                                    data: .init(name: title, color: colors.text, type: .selectable(selected), viewType: viewType, enabled: enabled, action: {
                preferences.setSelection(choice)
            })))
        }
        addChoice(.automatic, title: receivedAudioTranscriptionLanguageTitle(.automatic), viewType: .singleItem)

        guard let locales else {
            entries.append(.loading)
            return InputDataSignalValue(entries: entries, animated: false)
        }

        if case let .locale(identifier) = selection,
           !locales.contains(where: { TranscriptionLanguage.localeIdentifierMatches($0.identifier, identifier) }) {
            entries.append(.sectionId(section, type: .normal))
            section += 1
            addChoice(selection, title: translate(key: "Gergram.Transcription.Language.Unavailable", [receivedAudioTranscriptionLanguageTitle(selection)]),
                      viewType: .singleItem, enabled: false)
        }
        entries.append(.sectionId(section, type: .normal))
        section += 1
        if !locales.isEmpty {
            entries.append(.search(sectionId: section, index: Int32(entries.count), value: .none, identifier: .init("transcription-language-search"), update: { state in
                navigation?.updateSearch(state.request.trimmingCharacters(in: .whitespacesAndNewlines))
            }))
        }
        let matches = locales.filter { transcriptionLanguageMatches($0, query: query) }
        for (index, locale) in matches.enumerated() {
            addChoice(.locale(locale.identifier), title: TranscriptionLanguage.displayName(for: locale), viewType: bestGeneralViewType(matches, for: index))
        }
        let hint: String
        if locales.isEmpty {
            hint = localizedString("Gergram.Transcription.Language.NoLanguages")
        } else if matches.isEmpty {
            hint = localizedString("Gergram.Transcription.Language.NoMatches")
        } else {
            hint = localizedString("Gergram.Transcription.Language.Hint")
        }
        entries.append(.desc(sectionId: section, index: Int32(entries.count), text: .plain(hint),
                             data: .init(color: colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: entries, animated: false)
    }
    let controller = InputDataController(dataSignal: signal, title: localizedString("Gergram.Transcription.Language"), hasDone: false)
    controller.contextObject = navigation
    controller.didAppear = { controller in
        navigation.table = controller.tableView
        controller.tableView.delegate = navigation
        guard let window = controller.window else { return }
        for (key, forward) in [(KeyboardKey.UpArrow, false), (.DownArrow, true)] {
            window.set(handler: { [weak controller] event in
                guard let controller, allowsLanguageNavigation(event, in: controller) else { return .invokeNext }
                return navigation.move(in: controller.tableView, forward: forward)
            }, with: controller, for: key, priority: .high)
        }
    }
    controller.returnKeyInvocation = { [weak controller] _, event in
        guard let controller, allowsLanguageNavigation(event, in: controller) else { return .invokeEvent }
        if event.isARepeat {
            return .nothing
        }
        return navigation.activate(in: controller.tableView) ? .nothing : .invokeEvent
    }
    return controller
}

private func allowsLanguageNavigation(_ event: NSEvent, in controller: InputDataController) -> Bool {
    let editingModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    guard event.modifierFlags.intersection(editingModifiers).isEmpty,
          let window = controller.window, controller.view.window === window else { return false }
    if let editor = window.firstResponder as? NSTextView {
        return editor is SearchTextField && editor.isDescendant(of: controller.view) && !editor.hasMarkedText()
    }
    return true
}
