import Foundation
import SwiftSignalKit

public enum BlockedSenderVisibilitySettings {
    private static let key = "gergram.chat.hideBlockedSenders"
    private static let enabled = ValuePromise(UserDefaults.standard.bool(forKey: key), ignoreRepeated: true)

    public static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: key)
    }

    public static func observe() -> Signal<Bool, NoError> {
        return enabled.get()
    }

    public static func setEnabled(_ value: Bool) {
        assert(Thread.isMainThread)
        UserDefaults.standard.set(value, forKey: key)
        enabled.set(value)
    }
}
