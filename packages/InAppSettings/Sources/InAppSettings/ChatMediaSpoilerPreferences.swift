import Foundation
import SwiftSignalKit

public final class ChatMediaSpoilerPreferences {
    public static let shared = ChatMediaSpoilerPreferences(defaults: .standard)

    private static let key = "Gergram.Chat.RevealMediaSpoilers"
    private let defaults: UserDefaults
    private let enabled: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.enabled = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: Self.key)
    }

    public var signal: Signal<Bool, NoError> {
        enabled.get()
    }

    public func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
        enabled.set(value)
    }
}
