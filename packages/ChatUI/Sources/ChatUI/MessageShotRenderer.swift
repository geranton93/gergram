import AppKit

enum MessageShotRenderer {
    struct Row {
        let header: NSAttributedString
        let body: NSAttributedString
        let background: NSColor
    }

    static let maximumMessageCount = 20

    static func png(rows: [Row], background: NSColor) -> Data? {
        guard !rows.isEmpty, rows.count <= maximumMessageCount,
              rows.reduce(0, { $0 + $1.header.length + $1.body.length }) <= 16_000 else {
            return nil
        }

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

        let metrics = rows.map { (header: height(of: $0.header), body: height(of: $0.body)) }
        let contentHeight = metrics.reduce(CGFloat(0)) { sum, row in
            sum + row.header + textSpacing + row.body + 2 * padding
        }
        let totalHeight = 2 * margin + contentHeight + CGFloat(rows.count - 1) * rowSpacing
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

        background.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: totalHeight)).fill()

        var y = margin
        for (row, layout) in zip(rows, metrics) {
            let cardHeight = layout.header + textSpacing + layout.body + 2 * padding
            let card = NSRect(x: margin, y: y, width: cardWidth, height: cardHeight)
            row.background.setFill()
            NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()

            let header = NSRect(x: card.minX + padding, y: card.minY + padding, width: textWidth, height: layout.header)
            row.header.draw(with: header, options: drawingOptions)
            let body = NSRect(x: header.minX, y: header.maxY + textSpacing, width: textWidth, height: layout.body)
            row.body.draw(with: body, options: drawingOptions)
            y = card.maxY + rowSpacing
        }

        guard let image = bitmap.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
