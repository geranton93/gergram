import Foundation
import GeneralRows
import InAppSettings
import InputDataUI
import Localization
import SwiftSignalKit
import TelegramTheme
import TGUIKit

private typealias TranscriptionLanguage = ReceivedAudioTranscriptionLanguagePreferences

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
    let search = ValuePromise("", ignoreRepeated: true)
    let discovery = Signal<[Locale]?, NoError> { subscriber in
        subscriber.putNext(TranscriptionLanguage.availableLocales())
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(.concurrentDefaultQueue())
    let locales: Signal<[Locale]?, NoError> = .single(nil) |> then(discovery)

    let signal = combineLatest(queue: prepareQueue, preferences.signal, locales, search.get(), appearanceSignal)
    |> map { selection, locales, query, appearance in
        var section: Int32 = 1
        let colors = appearance.presentation.colors
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        func addChoice(_ choice: TranscriptionLanguage.Selection, title: String, viewType: GeneralViewType, enabled: Bool = true) {
            let id: String
            switch choice {
            case .automatic: id = "transcription-language-automatic"
            case let .locale(identifier): id = "transcription-language-\(identifier)"
            }
            let selected: Bool
            if case let .locale(current) = selection, case let .locale(candidate) = choice {
                selected = TranscriptionLanguage.localeIdentifierMatches(current, candidate)
            } else {
                selected = selection == choice
            }
            entries.append(.general(sectionId: section, index: Int32(entries.count), value: .none, error: nil, identifier: .init(id),
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
                search.set(state.request.trimmingCharacters(in: .whitespacesAndNewlines))
            }))
        }
        let matches = locales.filter { locale in
            query.isEmpty || TranscriptionLanguage.displayName(for: locale).localizedStandardContains(query)
                || locale.localizedString(forIdentifier: locale.identifier)?.localizedStandardContains(query) == true
                || locale.identifier.localizedStandardContains(query)
        }
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
    return InputDataController(dataSignal: signal, title: localizedString("Gergram.Transcription.Language"), hasDone: false)
}
