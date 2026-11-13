import Foundation
import Speech
import SwiftSignalKit

public final class ReceivedAudioTranscriptionLanguagePreferences {
    public enum Selection: Equatable {
        case automatic
        case locale(String)

        fileprivate init(storedIdentifier: String?) {
            guard let identifier = storedIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty else {
                self = .automatic
                return
            }
            self = .locale(Self.normalizedIdentifier(identifier))
        }

        fileprivate static func normalizedIdentifier(_ identifier: String) -> String {
            Locale(identifier: identifier.replacingOccurrences(of: "-", with: "_")).identifier
        }
    }

    public static let shared = ReceivedAudioTranscriptionLanguagePreferences(defaults: .standard)

    private static let key = "Gergram.Chat.ReceivedAudioTranscriptionLanguage"
    private let defaults: UserDefaults
    private let current: ValuePromise<Selection>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.current = ValuePromise(Selection(storedIdentifier: defaults.string(forKey: Self.key)), ignoreRepeated: true)
    }

    public var selection: Selection {
        Selection(storedIdentifier: defaults.string(forKey: Self.key))
    }

    public var signal: Signal<Selection, NoError> {
        current.get()
    }

    public func setSelection(_ selection: Selection) {
        switch selection {
        case .automatic:
            defaults.removeObject(forKey: Self.key)
        case let .locale(identifier):
            defaults.set(identifier, forKey: Self.key)
        }
        current.set(self.selection)
    }

    public static func availableLocales() -> [Locale] {
        guard #available(macOS 10.15, *) else { return [] }
        let displayLocale = Locale.current
        return SFSpeechRecognizer.supportedLocales().filter { locale in
            guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
            return recognizer.supportsOnDeviceRecognition && localeIdentifierMatches(recognizer.locale.identifier, locale.identifier)
        }.map { (locale: $0, name: displayName(for: $0, displayLocale: displayLocale)) }
            .sorted { lhs, rhs in
                let result = lhs.name.compare(rhs.name, options: [.caseInsensitive], locale: displayLocale)
                return result == .orderedSame ? lhs.locale.identifier < rhs.locale.identifier : result == .orderedAscending
            }.map(\.locale)
    }

    public static func displayName(for locale: Locale, displayLocale: Locale = .current) -> String {
        displayLocale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    public static func localeIdentifierMatches(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = Selection.normalizedIdentifier(lhs)
        let rhs = Selection.normalizedIdentifier(rhs)
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}
