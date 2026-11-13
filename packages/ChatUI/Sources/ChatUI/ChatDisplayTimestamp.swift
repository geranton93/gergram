import Foundation
import TelegramUtils

enum ChatDisplayTimestamp {
    private static let timeWithSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let fullDateWithMinutes: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    static func fullDate(for date: Date, showsSeconds: Bool) -> String {
        let formatter = showsSeconds ? DateSelectorUtil.chatFullDateFormatter : fullDateWithMinutes
        return formatter.string(from: date)
    }

    static func time(for date: Date, showsSeconds: Bool) -> String {
        let formatter = showsSeconds ? timeWithSeconds : DateSelectorUtil.chatDateFormatter
        return formatter.string(from: date)
    }

    static func serviceTime(
        timestamp: Int32, timeDifference: TimeInterval, showsSeconds: Bool,
        isRealMessage: Bool, hasText: Bool, isScheduledWhenOnline: Bool
    ) -> String? {
        guard isRealMessage, hasText, timestamp > 0, !isScheduledWhenOnline else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) - timeDifference)
        return time(for: date, showsSeconds: showsSeconds)
    }
}
