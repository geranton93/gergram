import Foundation
import TelegramCore

enum ProfileJoinDate {
    static func timestamp(for channel: TelegramChannel) -> Int32? {
        let isFullPeer: Bool
        if case .personal = channel.accessHash {
            isFullPeer = true
        } else {
            isFullPeer = false
        }
        return membershipTimestamp(channel.creationDate, isMember: channel.participationStatus == .member,
                                   isCreator: channel.flags.contains(.isCreator), isFullPeer: isFullPeer)
    }

    static func membershipTimestamp(_ timestamp: Int32, isMember: Bool, isCreator: Bool, isFullPeer: Bool) -> Int32? {
        guard isMember, !isCreator, isFullPeer, timestamp > 0 else {
            return nil
        }
        return timestamp
    }

    static func label(for timestamp: Int32, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}
