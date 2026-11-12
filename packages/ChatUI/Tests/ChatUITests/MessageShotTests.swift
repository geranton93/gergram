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
}
