import Foundation
import SwiftSignalKit

public final class ComposerEmojiHoverPreferences {
    public static let shared = ComposerEmojiHoverPreferences(defaults: .standard)

    private static let key = "gergram.composer.opensEmojiPickerOnHover"
    private let defaults: UserDefaults
    private let enabled: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.enabled = ValuePromise(defaults.object(forKey: Self.key) as? Bool ?? true, ignoreRepeated: true)
    }

    public var isEnabled: Bool {
        defaults.object(forKey: Self.key) as? Bool ?? true
    }

    public var signal: Signal<Bool, NoError> {
        enabled.get()
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
        self.enabled.set(enabled)
    }
}
