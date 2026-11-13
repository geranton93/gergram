import Foundation
import SwiftSignalKit

public final class PremiumStatusVisibilityPreferences {
    public static let shared = PremiumStatusVisibilityPreferences(defaults: .standard)

    private static let key = "gergram.chat.hidePremiumStatuses"
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

    public func setHidden(_ isHidden: Bool) {
        defaults.set(isHidden, forKey: Self.key)
        hidden.set(isHidden)
    }
}
