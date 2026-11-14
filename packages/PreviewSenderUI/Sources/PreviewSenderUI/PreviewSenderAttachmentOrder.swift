import Foundation

struct PreviewSenderAttachmentOrder: Equatable {
    enum Layout: Equatable {
        case items
        case sticker
        case albums
        case archive
    }

    static let albumSize = 10

    let urls: [URL]
    let layout: Layout
    private let revision = UUID()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision
    }

    func updating(urls: [URL], layout: Layout) -> Self {
        if self.urls == urls, self.layout == layout { return self }
        return Self(urls: urls, layout: layout)
    }

    var rowCount: Int {
        switch layout {
        case .items, .sticker: return urls.count
        case .albums: return urls.isEmpty ? 0 : (urls.count - 1) / Self.albumSize + 1
        case .archive: return urls.isEmpty ? 0 : 1
        }
    }

    func range(forRow row: Int) -> Range<Int>? {
        guard row >= 0, row < rowCount else { return nil }
        switch layout {
        case .items, .sticker:
            return row..<(row + 1)
        case .albums:
            let start = row * Self.albumSize
            return start..<min(start + Self.albumSize, urls.count)
        case .archive:
            return urls.indices
        }
    }

    func movingRows(from: Int, to: Int) -> [URL]? {
        guard from != to, let source = range(forRow: from), let destination = range(forRow: to) else { return nil }
        let insertion = from < to ? destination.upperBound - source.count : destination.lowerBound
        var reordered = urls
        let moved = reordered[source]
        reordered.removeSubrange(source)
        reordered.insert(contentsOf: moved, at: insertion)
        return reordered
    }

    func movingItem(from: Int, to: Int, inAlbum row: Int) -> [URL]? {
        guard layout == .albums, let range = range(forRow: row),
              from != to, (0..<range.count).contains(from), (0..<range.count).contains(to) else { return nil }
        var reordered = urls
        let url = reordered.remove(at: range.lowerBound + from)
        reordered.insert(url, at: range.lowerBound + to)
        return reordered
    }
}
