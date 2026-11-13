import Foundation
import SwiftSignalKit

public final class SwitchAnimationPreferences {
    public static let shared = SwitchAnimationPreferences(defaults: .standard)

    private static let disabledKey = "gergram.appearance.disableSwitchAnimations"
    private let defaults: UserDefaults
    private let value: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.value = ValuePromise(!defaults.bool(forKey: Self.disabledKey), ignoreRepeated: true)
    }

    public var isEnabled: Bool {
        !defaults.bool(forKey: Self.disabledKey)
    }

    public var signal: Signal<Bool, NoError> {
        value.get()
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(!enabled, forKey: Self.disabledKey)
        value.set(enabled)
    }
}
