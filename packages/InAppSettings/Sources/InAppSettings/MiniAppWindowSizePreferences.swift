import Foundation

public struct MiniAppWindowSizePreferences {
    public enum Dimension: String, CaseIterable {
        case width
        case height

        fileprivate var storageKey: String {
            "gergram.miniAppWindow.enlarge.\(rawValue)"
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnlarged(_ dimension: Dimension) -> Bool {
        defaults.bool(forKey: dimension.storageKey)
    }

    public func setEnlarged(_ enlarged: Bool, for dimension: Dimension) {
        defaults.set(enlarged, forKey: dimension.storageKey)
    }
}
