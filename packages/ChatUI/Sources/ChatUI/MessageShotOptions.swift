import Foundation

struct MessageShotOptions {
    private static let showsTimestampsKey = "gergram.messageShot.showsTimestamps"

    var showsTimestamps: Bool

    init(defaults: UserDefaults = .standard) {
        showsTimestamps = defaults.object(forKey: Self.showsTimestampsKey) as? Bool ?? true
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(showsTimestamps, forKey: Self.showsTimestampsKey)
    }

    func headerTitle(author: String?, timestamp: @autoclosure () -> String) -> String {
        [author, showsTimestamps ? timestamp() : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
