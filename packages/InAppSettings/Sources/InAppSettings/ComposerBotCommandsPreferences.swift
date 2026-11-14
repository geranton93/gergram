import Foundation
import SwiftSignalKit

public final class ComposerBotCommandsPreferences {
    public static let shared = ComposerBotCommandsPreferences(defaults: .standard)

    private static let key = "gergram.composer.hidesBotCommandsButton"
    private let defaults: UserDefaults
    private let hidden: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.hidden = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var hidesButton: Bool {
        defaults.bool(forKey: Self.key)
    }

    public var signal: Signal<Bool, NoError> {
        hidden.get()
    }

    public func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.key)
        self.hidden.set(hidden)
    }
}
