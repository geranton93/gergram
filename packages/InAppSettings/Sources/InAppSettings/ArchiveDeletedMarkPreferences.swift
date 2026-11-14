import Foundation
import SwiftSignalKit

public final class ArchiveDeletedMarkPreferences {
    public static let shared = ArchiveDeletedMarkPreferences(defaults: .standard)
    public static let defaultMark = "🧹"
    public static let maximumCustomTextUTF16Length = ChatIndicatorCustomText.maximumUTF16Length

    private static let key = "Gergram.Archive.DeletedMark"
    private let defaults: UserDefaults
    private let current: ValuePromise<String>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.current = ValuePromise(Self.load(from: defaults), ignoreRepeated: true)
    }

    public var mark: String {
        Self.load(from: defaults)
    }

    public var signal: Signal<String, NoError> {
        current.get()
    }

    @discardableResult
    public func setCustomMark(_ value: String) -> Bool {
        guard let text = ChatIndicatorCustomText.validated(value) else { return false }
        if text.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(text, forKey: Self.key)
        }
        current.set(mark)
        return true
    }

    private static func load(from defaults: UserDefaults) -> String {
        guard let value = defaults.string(forKey: key).flatMap(ChatIndicatorCustomText.validated), !value.isEmpty else {
            return defaultMark
        }
        return value
    }
}
