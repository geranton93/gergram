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
