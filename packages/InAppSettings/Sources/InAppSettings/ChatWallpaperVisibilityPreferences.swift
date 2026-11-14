import Foundation
import SwiftSignalKit

public final class ChatWallpaperVisibilityPreferences {
    public static let shared = ChatWallpaperVisibilityPreferences(defaults: .standard)

    private static let key = "gergram.chat.hideCustomWallpapers"
    private let defaults: UserDefaults
    private let isHidden: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.isHidden = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var signal: Signal<Bool, NoError> {
        isHidden.get()
    }

    public func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.key)
        isHidden.set(hidden)
    }
}
