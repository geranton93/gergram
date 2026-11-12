import AppKit
import XCTest
@testable import ChatUI

final class MessageShotTests: XCTestCase {
    func testTimestampPreferenceDefaultsToVisibleAndPersistsBothValues() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertTrue(options.showsTimestamps)

        options.showsTimestamps = false
        options.save(to: defaults)
        let reader = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertFalse(MessageShotOptions(defaults: reader).showsTimestamps)

        options.showsTimestamps = true
        options.save(to: defaults)
        XCTAssertTrue(MessageShotOptions(defaults: reader).showsTimestamps)
    }

    func testHeaderOmitsTimestampAndSeparatorsWhenHidden() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertEqual(options.headerTitle(author: "Author", timestamp: "Date"), "Author • Date")
        XCTAssertEqual(options.headerTitle(author: nil, timestamp: "Date"), "Date")

        options.showsTimestamps = false
        XCTAssertEqual(options.headerTitle(author: "Author", timestamp: "Date"), "Author")
        XCTAssertEqual(options.headerTitle(author: nil, timestamp: "Date"), "")
    }

    func testBackgroundDefaultsToVisibleAndPersistsIndependentlyOfTimestamps() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "gergram.messageShot.showsTimestamps")

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertTrue(options.showsBackground)
        XCTAssertFalse(options.showsTimestamps)

        options.showsBackground = false
        options.save(to: defaults)
        let reader = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var savedOptions = MessageShotOptions(defaults: reader)
        XCTAssertFalse(savedOptions.showsBackground)
        XCTAssertFalse(savedOptions.showsTimestamps)

        savedOptions.showsTimestamps = true
        savedOptions.save(to: reader)
        options = MessageShotOptions(defaults: defaults)
        XCTAssertFalse(options.showsBackground)
        XCTAssertTrue(options.showsTimestamps)

        options.showsBackground = true
        options.save(to: defaults)
        XCTAssertTrue(MessageShotOptions(defaults: reader).showsBackground)
    }

    func testTransparentCanvasPreservesMessageCardAndImageSize() throws {
        let row = MessageShotRenderer.Row(
            header: NSAttributedString(string: ""),
            body: NSAttributedString(string: "Message body", attributes: [.font: NSFont.systemFont(ofSize: 14)]),
            background: .red
        )
        let filledPNG = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: .white))
        let transparentPNG = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        let filled = try XCTUnwrap(NSBitmapImageRep(data: filledPNG))
        let transparent = try XCTUnwrap(NSBitmapImageRep(data: transparentPNG))

        XCTAssertEqual(transparent.pixelsWide, filled.pixelsWide)
        XCTAssertEqual(transparent.pixelsHigh, filled.pixelsHigh)
        let filledCanvas = try XCTUnwrap(filled.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(filledCanvas.alphaComponent, 1)
        XCTAssertEqual(try XCTUnwrap(transparent.colorAt(x: 0, y: 0)).alphaComponent, 0)

        let x = filled.pixelsWide / 2
        let y = filled.pixelsHigh / 2
        let filledCard = try XCTUnwrap(filled.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let transparentCard = try XCTUnwrap(transparent.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        XCTAssertNotEqual(filledCard, filledCanvas)
        XCTAssertEqual(transparentCard, filledCard)
        XCTAssertEqual(transparentCard.alphaComponent, 1)
    }

    func testEmptyHeaderUsesNoVerticalSpace() throws {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        let body = NSAttributedString(string: "Message body", attributes: attributes)
        let header = NSAttributedString(string: "Author • Timestamp", attributes: attributes)
        let emptyHeader = NSAttributedString(string: "", attributes: attributes)

        func render(_ header: NSAttributedString) throws -> NSBitmapImageRep {
            let row = MessageShotRenderer.Row(header: header, body: body, background: .white)
            let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: .white))
            return try XCTUnwrap(NSBitmapImageRep(data: png))
        }

        let imageWithHeader = try render(header)
        let imageWithoutHeader = try render(emptyHeader)
        let headerHeight = ceil(header.boundingRect(
            with: NSSize(width: 504, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)

        XCTAssertEqual(imageWithoutHeader.pixelsWide, imageWithHeader.pixelsWide)
        XCTAssertEqual(imageWithHeader.pixelsHigh - imageWithoutHeader.pixelsHigh, Int((headerHeight + 4) * 2))
    }

    func testMissingThumbnailKeepsAttachmentLabel() throws {
        let body = text("A caption")
        let label = text("[Photo]")
        let attachment = MessageShotRenderer.Attachment(label: label, thumbnail: nil)
        let row = MessageShotRenderer.Row(header: text(""), body: body, background: .white, attachments: [attachment])
        let original = MessageShotRenderer.Row(header: text(""), body: text("A caption\n[Photo]"), background: .white)

        XCTAssertEqual(
            try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil)),
            try XCTUnwrap(MessageShotRenderer.png(rows: [original], background: nil))
        )
    }

    func testThumbnailIsDrawnWithOriginalOrientation() throws {
        let thumbnail = try testImage(width: 40, height: 80)
        let row = MessageShotRenderer.Row(
            header: text(""), body: text(""), background: .white,
            attachments: [.init(label: text("[Photo]"), thumbnail: thumbnail)]
        )
        let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        let top = try XCTUnwrap(image.colorAt(x: 65, y: 66)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(image.colorAt(x: 65, y: 120)?.usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(top.redComponent, top.blueComponent)
        XCTAssertGreaterThan(bottom.blueComponent, bottom.redComponent)
        XCTAssertEqual(try XCTUnwrap(image.colorAt(x: 0, y: 0)).alphaComponent, 0)
    }

    func testOversizedPreviewLayoutFallsBackToPlaceholders() throws {
        let thumbnail = try testImage(width: 400, height: 400)
        let label = text("[Photo]")
        let preview = MessageShotRenderer.Row(
            header: text(""), body: text(""), background: .white,
            attachments: [.init(label: label, thumbnail: thumbnail)]
        )
        let placeholder = MessageShotRenderer.Row(header: text(""), body: label, background: .white)

        XCTAssertEqual(
            try XCTUnwrap(MessageShotRenderer.png(rows: Array(repeating: preview, count: 20), background: nil)),
            try XCTUnwrap(MessageShotRenderer.png(rows: Array(repeating: placeholder, count: 20), background: nil))
        )
    }

    func testCachedThumbnailDownsamplesAndRejectsCorruptData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = NSBitmapImageRep(cgImage: try testImage(width: 1600, height: 800))
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)

        let thumbnail = try XCTUnwrap(MessageShotRenderer.thumbnail(at: url.path))
        XCTAssertEqual(thumbnail.width, 640)
        XCTAssertEqual(thumbnail.height, 320)

        try Data([0, 1, 2, 3]).write(to: url)
        XCTAssertNil(MessageShotRenderer.thumbnail(at: url.path))
    }

    func testCachedThumbnailRejectsOversizedFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = NSBitmapImageRep(cgImage: try testImage(width: 4, height: 4))
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
        let file = try FileHandle(forWritingTo: url)
        file.truncateFile(atOffset: 8 * 1024 * 1024 + 1)
        file.closeFile()

        XCTAssertNil(MessageShotRenderer.thumbnail(at: url.path))
    }

    private func text(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14)])
    }

    private func testImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }
}
