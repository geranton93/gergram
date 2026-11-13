import Foundation

struct ChatMessageDetails {
    enum Field: String, CaseIterable {
        case id = "Id"
        case sent = "Sent"
        case edited = "Edited"
        case forwarded = "Forwarded"
        case views = "Views"
        case forwards = "Forwards"
        case fileSize = "FileSize"
        case mimeType = "MimeType"
        case fileName = "FileName"
        case resolution = "Resolution"
        case mediaDataCenter = "MediaDataCenter"

        func menuValue(_ value: String) -> String {
            let limit = self == .fileName ? 40 : 64
            guard let overflow = value.index(value.startIndex, offsetBy: limit, limitedBy: value.endIndex),
                  overflow < value.endIndex else { return value }
            return "…" + String(value.suffix(limit))
        }
    }

    struct MediaDetails {
        let fileSize: Int64?
        let mimeType: String?
        let fileName: String?
        let dimensions: (width: Int32, height: Int32)?
        let dataCenter: Int?

        var pixelArea: Int64 {
            guard let dimensions, dimensions.width > 0, dimensions.height > 0 else { return 0 }
            return Int64(dimensions.width) * Int64(dimensions.height)
        }
    }

    let id: Int32
    let sentAt: Int32
    let editedAt: Int32?
    let forwardedAt: Int32?
    let views: Int?
    let forwards: Int?
    let media: MediaDetails?

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
        case .fileSize:
            guard let size = media?.fileSize, size > 0 else { return nil }
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        case .mimeType:
            return Self.visibleMetadata(media?.mimeType)
        case .fileName:
            return Self.visibleMetadata(media?.fileName)
        case .resolution:
            guard let dimensions = media?.dimensions, dimensions.width > 0, dimensions.height > 0 else { return nil }
            return "\(dimensions.width) × \(dimensions.height)"
        case .mediaDataCenter:
            return Self.positiveCount(media?.dataCenter)
        }
    }

    private static func visibleMetadata(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 4_096, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: { scalar in
                  switch scalar.value {
                  case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                      return true
                  default:
                      return false
                  }
              }) else { return nil }
        return value
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
