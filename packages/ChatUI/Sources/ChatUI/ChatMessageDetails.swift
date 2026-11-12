import Foundation

struct ChatMessageDetails {
    enum Field: String, CaseIterable {
        case id = "Id"
        case sent = "Sent"
        case edited = "Edited"
        case forwarded = "Forwarded"
        case views = "Views"
        case forwards = "Forwards"
    }

    let id: Int32
    let sentAt: Int32
    let editedAt: Int32?
    let forwardedAt: Int32?
    let views: Int?
    let forwards: Int?

    func value(for field: Field, dateFormatter: DateFormatter) -> String? {
        switch field {
        case .id:
            return String(id)
        case .sent:
            return Self.date(sentAt, formatter: dateFormatter)
        case .edited:
            return Self.date(editedAt, formatter: dateFormatter)
        case .forwarded:
            return Self.date(forwardedAt, formatter: dateFormatter)
        case .views:
            return Self.positiveCount(views)
        case .forwards:
            return Self.positiveCount(forwards)
        }
    }

    private static func date(_ timestamp: Int32?, formatter: DateFormatter) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func positiveCount(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return String(count)
    }
}
