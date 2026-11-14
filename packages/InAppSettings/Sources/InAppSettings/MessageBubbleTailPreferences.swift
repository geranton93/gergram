import Foundation
import SwiftSignalKit

public final class MessageBubbleTailPreferences {
    public static let shared = MessageBubbleTailPreferences(defaults: .standard)

    private static let key = "gergram.chat.hideMessageTails"
    private let defaults: UserDefaults
    private let hidden: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.hidden = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var isHidden: Bool {
        defaults.bool(forKey: Self.key)
    }

    public var signal: Signal<Bool, NoError> {
        hidden.get()
    }

    public func setHidden(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
        hidden.set(value)
    }
}
