import Foundation
import SwiftSignalKit

public final class ProfileJoinDatePreferences {
    public static let shared = ProfileJoinDatePreferences(defaults: .standard)

    private static let key = "Gergram.Profile.ShowJoinDate"
    private let defaults: UserDefaults
    private let visibility: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.visibility = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var signal: Signal<Bool, NoError> {
        visibility.get()
    }

    public func setVisible(_ visible: Bool) {
        defaults.set(visible, forKey: Self.key)
        visibility.set(visible)
    }
}
