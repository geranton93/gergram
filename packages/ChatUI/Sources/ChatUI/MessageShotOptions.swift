import ColorPalette
import Foundation

struct MessageShotOptions {
    enum Theme: String, CaseIterable {
        case current
        case dayClassic
        case day
        case dark
        case nightAccent

        func palette(current: ColorPalette) -> ColorPalette {
            switch self {
            case .current: return current
            case .dayClassic: return TelegramBuiltinTheme.dayClassic.palette
            case .day: return TelegramBuiltinTheme.day.palette
            case .dark: return TelegramBuiltinTheme.dark.palette
            case .nightAccent: return TelegramBuiltinTheme.nightAccent.palette
            }
        }
    }

    private static let showsTimestampsKey = "gergram.messageShot.showsTimestamps"
    private static let showsBackgroundKey = "gergram.messageShot.showsBackground"
    private static let showsReactionsKey = "gergram.messageShot.showsReactions"
    private static let themeKey = "gergram.messageShot.theme"

    var showsTimestamps: Bool
    var showsBackground: Bool
    var showsReactions: Bool
    var theme: Theme

    init(defaults: UserDefaults = .standard) {
        showsTimestamps = defaults.object(forKey: Self.showsTimestampsKey) as? Bool ?? true
        showsBackground = defaults.object(forKey: Self.showsBackgroundKey) as? Bool ?? true
        showsReactions = defaults.object(forKey: Self.showsReactionsKey) as? Bool ?? false
        theme = defaults.string(forKey: Self.themeKey).flatMap(Theme.init(rawValue:)) ?? .current
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(showsTimestamps, forKey: Self.showsTimestampsKey)
        defaults.set(showsBackground, forKey: Self.showsBackgroundKey)
        defaults.set(showsReactions, forKey: Self.showsReactionsKey)
        defaults.set(theme.rawValue, forKey: Self.themeKey)
    }

    func headerTitle(author: String?, timestamp: @autoclosure () -> String) -> String {
        [author, showsTimestamps ? timestamp() : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    func reactionSummary(_ reactions: some Sequence<(label: String, count: Int)>) -> String {
        guard showsReactions else { return "" }
        var labels: [String] = []
        for (label, count) in reactions where count > 0 && !label.isEmpty && label.utf16.count <= 64 {
            if labels.count == 16 {
                labels.append("…")
                break
            }
            labels.append("\(label) \(count)")
        }
        return labels.joined(separator: "   ")
    }
}
