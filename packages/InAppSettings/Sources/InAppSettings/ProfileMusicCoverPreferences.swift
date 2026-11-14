import Foundation
import SwiftSignalKit

public final class ProfileMusicCoverPreferences {
    public static let shared = ProfileMusicCoverPreferences(defaults: .standard)

    private static let key = "gergram.profile.adaptiveMusicCover"
    private let defaults: UserDefaults
    private let adaptive: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.adaptive = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    public var isAdaptive: Bool {
        Self.read(from: defaults)
    }

    public var signal: Signal<Bool, NoError> {
        adaptive.get()
    }

    public func setAdaptive(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
        adaptive.set(value)
    }

    private static func read(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Self.key) == nil || defaults.bool(forKey: Self.key)
    }
}
