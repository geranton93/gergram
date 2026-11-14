import AppKit
import CoreText
import ImageIO

enum MessageShotRenderer {
    struct Attachment {
        let label: NSAttributedString
        let thumbnail: CGImage?
    }

    struct Reply {
        let title: NSAttributedString
        let excerpt: NSAttributedString
        let accent: NSColor

        static func excerpt(source: String, quote: String? = nil, quoteOffset: Int? = nil) -> String? {
            let sourceLength = source.utf16.prefix(16_001).count
            guard sourceLength <= 16_000 else { return nil }

            let text: String
            if let quote {
                let quoteLength = quote.utf16.prefix(sourceLength + 1).count
                guard let offset = quoteOffset, offset >= 0, quoteLength > 0, quoteLength <= sourceLength,
                      offset <= sourceLength - quoteLength,
                      let range = Range(NSRange(location: offset, length: quoteLength), in: source),
                      source[range].utf16.elementsEqual(quote.utf16) else {
                    return nil
                }
                text = String(source[range])
            } else {
                text = source
            }

            let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !oneLine.isEmpty else { return nil }
            var excerpt = ""
            var remaining = 139
            for character in oneLine {
                let length = character.utf16.count
                guard length <= remaining else { return excerpt + "…" }
                excerpt.append(character)
                remaining -= length
            }
            return excerpt
        }
    }

    struct Row {
        let header: NSAttributedString
        let headerDecoration: HeaderDecoration?
        let body: NSAttributedString
        let background: NSColor
        let reply: Reply?
        let attachments: [Attachment]
        let footer: NSAttributedString?

        init(header: NSAttributedString, headerDecoration: HeaderDecoration? = nil, body: NSAttributedString, background: NSColor, reply: Reply? = nil, attachments: [Attachment] = [], footer: NSAttributedString? = nil) {
            self.header = header
            self.headerDecoration = headerDecoration
            self.body = body
            self.background = background
            self.reply = reply
            self.attachments = attachments
            self.footer = footer
        }
    }

    struct HeaderDecoration {
        let label: String
        let foreground: NSColor
        let background: NSColor
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
        case reply(Reply)
    }

    private struct RowLayout {
        let headerHeight: CGFloat
        let headerTextWidth: CGFloat
        let decoration: DecorationLayout?
        let parts: [(Part, CGSize)]
        let height: CGFloat
    }

    private struct DecorationLayout {
        let line: CTLine
        let ascent: CGFloat
        let background: NSColor
        let size: CGSize
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
            let replyLength = row.reply.map { $0.title.length + $0.excerpt.length } ?? 0
            return length + row.header.length + (row.headerDecoration?.label.utf16.count ?? 0) + row.body.length + labels + separators + replyLength + (row.footer?.length ?? 0)
        }
        guard textLength <= 16_000 else { return nil }

        let width: CGFloat = 560
        let margin: CGFloat = 16
        let padding: CGFloat = 12
        let rowSpacing: CGFloat = 8
        let textSpacing: CGFloat = 4
        let replyPadding: CGFloat = 8
        let replySpacing: CGFloat = 2
        let cardWidth = width - 2 * margin
        let textWidth = cardWidth - 2 * padding
        let drawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let decorationHorizontalPadding: CGFloat = 6
        let decorationVerticalPadding: CGFloat = 2
        let decorationSpacing: CGFloat = 8
        let maximumDecorationWidth: CGFloat = 140
        let decorationFont = NSFont.systemFont(ofSize: 11, weight: .medium)

        func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
            ceil(text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: drawingOptions).height)
        }
        let replyTextWidth = textWidth - 2 * replyPadding
        func replyHeight(_ reply: Reply) -> CGFloat {
            2 * replyPadding + height(of: reply.title, width: replyTextWidth)
                + replySpacing + height(of: reply.excerpt, width: replyTextWidth)
        }

        func measureDecoration(_ decoration: HeaderDecoration) -> DecorationLayout {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: decorationFont,
                .foregroundColor: decoration.foreground
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: decoration.label, attributes: attributes))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let naturalWidth = ceil(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let contentWidth = min(naturalWidth, maximumDecorationWidth - 2 * decorationHorizontalPadding)
            let displayLine: CTLine
            if naturalWidth > contentWidth {
                let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                displayLine = CTLineCreateTruncatedLine(line, contentWidth, .end, ellipsis) ?? ellipsis
            } else {
                displayLine = line
            }
            return DecorationLayout(
                line: displayLine, ascent: ascent, background: decoration.background,
                size: CGSize(width: contentWidth + 2 * decorationHorizontalPadding,
                             height: ceil(ascent + descent) + 2 * decorationVerticalPadding)
            )
        }

        func measure(withThumbnails: Bool) -> [RowLayout] {
            rows.map { row in
                let decoration = row.headerDecoration.map(measureDecoration)
                let headerTextWidth = textWidth - (decoration.map { $0.size.width + decorationSpacing } ?? 0)
                let headerTextHeight = row.header.length == 0 ? 0 : height(of: row.header, width: headerTextWidth)
                let header = max(headerTextHeight, decoration?.size.height ?? 0)
                var content: [Part] = row.reply.map { [.reply($0)] } ?? []
                content += parts(for: row, withThumbnails: withThumbnails)
                if let footer = row.footer, footer.length > 0 {
                    content.append(.text(footer))
                }
                let parts = content.map { part -> (Part, CGSize) in
                    switch part {
                    case let .text(text):
                        return (part, CGSize(width: textWidth, height: height(of: text, width: textWidth)))
                    case let .reply(reply):
                        return (part, CGSize(width: textWidth, height: replyHeight(reply)))
                    case let .image(image):
                        let scale = min(0.5, textWidth / CGFloat(image.width), 160 / CGFloat(image.height))
                        return (part, CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
                    }
                }
                let spacingCount = max(0, parts.count - (header > 0 ? 0 : 1))
                let body = parts.reduce(CGFloat(0)) { $0 + $1.1.height }
                return RowLayout(headerHeight: header, headerTextWidth: headerTextWidth, decoration: decoration, parts: parts, height: header + body + CGFloat(spacingCount) * textSpacing + 2 * padding)
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
                let header = NSRect(x: textX, y: textY, width: layout.headerTextWidth, height: layout.headerHeight)
                row.header.draw(with: header, options: drawingOptions)
                if let decoration = layout.decoration {
                    let x = textX + textWidth - decoration.size.width
                    let rect = CGRect(origin: CGPoint(x: x, y: textY), size: decoration.size)
                    decoration.background.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
                    bitmap.saveGState()
                    bitmap.clip(to: rect)
                    bitmap.translateBy(x: rect.minX + decorationHorizontalPadding, y: rect.minY + decorationVerticalPadding + decoration.ascent)
                    bitmap.scaleBy(x: 1, y: -1)
                    bitmap.textMatrix = .identity
                    bitmap.textPosition = .zero
                    CTLineDraw(decoration.line, bitmap)
                    bitmap.restoreGState()
                }
                textY += layout.headerHeight + textSpacing
            }
            for (part, size) in layout.parts {
                let rect = NSRect(origin: NSPoint(x: textX, y: textY), size: size)
                switch part {
                case let .text(text):
                    text.draw(with: rect, options: drawingOptions)
                case let .reply(reply):
                    reply.accent.withAlphaComponent(0.12).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                    reply.accent.setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height), xRadius: 1, yRadius: 1).fill()
                    let titleHeight = height(of: reply.title, width: replyTextWidth)
                    let x = rect.minX + replyPadding
                    let y = rect.minY + replyPadding
                    reply.title.draw(with: NSRect(x: x, y: y, width: replyTextWidth, height: titleHeight), options: drawingOptions)
                    let excerptY = y + titleHeight + replySpacing
                    reply.excerpt.draw(with: NSRect(x: x, y: excerptY, width: replyTextWidth, height: rect.maxY - replyPadding - excerptY), options: drawingOptions)
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
