import AppKit
import ImageIO

enum MessageShotRenderer {
    struct Attachment {
        let label: NSAttributedString
        let thumbnail: CGImage?
    }

    struct Row {
        let header: NSAttributedString
        let body: NSAttributedString
        let background: NSColor
        let attachments: [Attachment]
        let footer: NSAttributedString?

        init(header: NSAttributedString, body: NSAttributedString, background: NSColor, attachments: [Attachment] = [], footer: NSAttributedString? = nil) {
            self.header = header
            self.body = body
            self.background = background
            self.attachments = attachments
            self.footer = footer
        }
    }

    struct SpoilerRedaction {
        let text: String
        private let hiddenRanges: [Range<Int>]

        init(text: String, spoilerRanges: [Range<Int>]) {
            let source = text as NSString
            var expandedRanges: [Range<Int>] = []
            for range in spoilerRanges {
                guard range.lowerBound >= 0, range.upperBound <= source.length, !range.isEmpty else {
                    self.text = String(repeating: "•", count: source.length)
                    self.hiddenRanges = [0..<source.length]
                    return
                }
                let composedRange = source.rangeOfComposedCharacterSequences(for: NSRange(location: range.lowerBound, length: range.count))
                expandedRanges.append(composedRange.location..<NSMaxRange(composedRange))
            }

            var mergedRanges: [Range<Int>] = []
            for range in expandedRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = mergedRanges.last, last.upperBound >= range.lowerBound {
                    mergedRanges[mergedRanges.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
                } else {
                    mergedRanges.append(range)
                }
            }

            let masked = NSMutableString(string: text)
            for range in mergedRanges {
                masked.replaceCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: String(repeating: "•", count: range.count))
            }
            self.text = masked as String
            self.hiddenRanges = mergedRanges
        }

        func permitsEntity(in range: Range<Int>) -> Bool {
            range.lowerBound >= 0 && range.upperBound <= text.utf16.count && !range.isEmpty
                && !hiddenRanges.contains(where: { $0.overlaps(range) })
        }
    }

    static let maximumMessageCount = 20
    private static let maximumThumbnailBytes = 8 * 1024 * 1024
    private static let maximumThumbnailPixels = 32_000_000.0
    private static let maximumThumbnailDimension = 640
    private static let thumbnailTypes: Set<String> = ["public.jpeg", "public.png", "public.heic", "public.heif", "org.webmproject.webp"]

    private enum Part {
        case text(NSAttributedString)
        case image(CGImage)
    }

    private struct RowLayout {
        let headerHeight: CGFloat
        let parts: [(Part, CGSize)]
        let height: CGFloat
    }

    static func thumbnail(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumThumbnailBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= maximumThumbnailBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), thumbnailTypes.contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width * height <= maximumThumbnailPixels else {
            return nil
        }

        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumThumbnailDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func parts(for row: Row, withThumbnails: Bool) -> [Part] {
        guard !row.attachments.isEmpty else { return row.body.length == 0 ? [] : [.text(row.body)] }
        var parts: [Part] = []
        var text = NSMutableAttributedString(attributedString: row.body)
        for attachment in row.attachments {
            if withThumbnails, let thumbnail = attachment.thumbnail {
                if text.length > 0 {
                    parts.append(.text(text))
                    text = NSMutableAttributedString(string: "")
                }
                parts.append(.image(thumbnail))
            } else {
                if text.length > 0 {
                    text.append(NSAttributedString(string: "\n", attributes: attachment.label.length > 0 ? attachment.label.attributes(at: 0, effectiveRange: nil) : nil))
                }
                text.append(attachment.label)
            }
        }
        if text.length > 0 {
            parts.append(.text(text))
        }
        return parts
    }

    static func png(rows: [Row], background: NSColor?) -> Data? {
        guard !rows.isEmpty, rows.count <= maximumMessageCount else { return nil }
        let textLength = rows.reduce(0) { length, row in
            let labels = row.attachments.reduce(0) { $0 + $1.label.length }
            let separators = max(0, row.attachments.count - (row.body.length == 0 ? 1 : 0))
            return length + row.header.length + row.body.length + labels + separators + (row.footer?.length ?? 0)
        }
        guard textLength <= 16_000 else { return nil }

        let width: CGFloat = 560
        let margin: CGFloat = 16
        let padding: CGFloat = 12
        let rowSpacing: CGFloat = 8
        let textSpacing: CGFloat = 4
        let cardWidth = width - 2 * margin
        let textWidth = cardWidth - 2 * padding
        let drawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        func height(of text: NSAttributedString) -> CGFloat {
            ceil(text.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude), options: drawingOptions).height)
        }

        func measure(withThumbnails: Bool) -> [RowLayout] {
            rows.map { row in
                let header = row.header.length == 0 ? 0 : height(of: row.header)
                var content = parts(for: row, withThumbnails: withThumbnails)
                if let footer = row.footer, footer.length > 0 {
                    content.append(.text(footer))
                }
                let parts = content.map { part -> (Part, CGSize) in
                    switch part {
                    case let .text(text):
                        return (part, CGSize(width: textWidth, height: height(of: text)))
                    case let .image(image):
                        let scale = min(0.5, textWidth / CGFloat(image.width), 160 / CGFloat(image.height))
                        return (part, CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
                    }
                }
                let spacingCount = max(0, parts.count - (header > 0 ? 0 : 1))
                let body = parts.reduce(CGFloat(0)) { $0 + $1.1.height }
                return RowLayout(headerHeight: header, parts: parts, height: header + body + CGFloat(spacingCount) * textSpacing + 2 * padding)
            }
        }
        let canvasInsets = 2 * margin + CGFloat(rows.count - 1) * rowSpacing
        var layouts = measure(withThumbnails: true)
        var totalHeight = canvasInsets + layouts.reduce(CGFloat(0)) { $0 + $1.height }
        if totalHeight > 3_000, rows.contains(where: { $0.attachments.contains { $0.thumbnail != nil } }) {
            layouts = measure(withThumbnails: false)
            totalHeight = canvasInsets + layouts.reduce(CGFloat(0)) { $0 + $1.height }
        }
        let scale: CGFloat = 2
        guard totalHeight.isFinite, totalHeight <= 3_000,
              let bitmap = CGContext(data: nil, width: Int(width * scale), height: Int(totalHeight * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        bitmap.scaleBy(x: scale, y: scale)
        bitmap.translateBy(x: 0, y: totalHeight)
        bitmap.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)

        let canvas = CGRect(x: 0, y: 0, width: width, height: totalHeight)
        if let background {
            background.setFill()
            NSBezierPath(rect: canvas).fill()
        } else {
            bitmap.clear(canvas)
        }

        var y = margin
        for (row, layout) in zip(rows, layouts) {
            let card = NSRect(x: margin, y: y, width: cardWidth, height: layout.height)
            row.background.setFill()
            NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()

            let textX = card.minX + padding
            var textY = card.minY + padding
            if layout.headerHeight > 0 {
                let header = NSRect(x: textX, y: textY, width: textWidth, height: layout.headerHeight)
                row.header.draw(with: header, options: drawingOptions)
                textY += layout.headerHeight + textSpacing
            }
            for (part, size) in layout.parts {
                let rect = NSRect(origin: NSPoint(x: textX, y: textY), size: size)
                switch part {
                case let .text(text):
                    text.draw(with: rect, options: drawingOptions)
                case let .image(image):
                    NSImage(cgImage: image, size: size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                textY += size.height + textSpacing
            }
            y = card.maxY + rowSpacing
        }

        guard let image = bitmap.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
