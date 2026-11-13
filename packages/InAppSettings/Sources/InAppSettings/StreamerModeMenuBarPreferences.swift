import Foundation
import SwiftSignalKit

public final class StreamerModeMenuBarPreferences {
    public static let shared = StreamerModeMenuBarPreferences(defaults: .standard)

    private static let key = "gergram.menuBar.showsStreamerMode"
    private let defaults: UserDefaults
    private let visibility: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.visibility = ValuePromise(defaults.object(forKey: Self.key) as? Bool ?? true, ignoreRepeated: true)
    }

    public var signal: Signal<Bool, NoError> {
        visibility.get()
    }

    public func setVisible(_ visible: Bool) {
        defaults.set(visible, forKey: Self.key)
        visibility.set(visible)
    }
}
