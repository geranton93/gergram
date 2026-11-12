import Foundation

struct MessageShotOptions {
    private static let showsTimestampsKey = "gergram.messageShot.showsTimestamps"
    private static let showsBackgroundKey = "gergram.messageShot.showsBackground"

    var showsTimestamps: Bool
    var showsBackground: Bool

    init(defaults: UserDefaults = .standard) {
        showsTimestamps = defaults.object(forKey: Self.showsTimestampsKey) as? Bool ?? true
        showsBackground = defaults.object(forKey: Self.showsBackgroundKey) as? Bool ?? true
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(showsTimestamps, forKey: Self.showsTimestampsKey)
        defaults.set(showsBackground, forKey: Self.showsBackgroundKey)
    }

    func headerTitle(author: String?, timestamp: @autoclosure () -> String) -> String {
        [author, showsTimestamps ? timestamp() : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
