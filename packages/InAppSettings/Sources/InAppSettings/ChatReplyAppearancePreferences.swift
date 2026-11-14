import Foundation
import SwiftSignalKit

public final class ChatReplyAppearancePreferences {
    public static let shared = ChatReplyAppearancePreferences(defaults: .standard)

    private static let key = "gergram.chat.simplifyQuotesAndReplies"
    private let defaults: UserDefaults
    private let simplified: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.simplified = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var isSimplified: Bool {
        defaults.bool(forKey: Self.key)
    }

    public var signal: Signal<Bool, NoError> {
        simplified.get()
    }

    public func setSimplified(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
        simplified.set(value)
    }
}
