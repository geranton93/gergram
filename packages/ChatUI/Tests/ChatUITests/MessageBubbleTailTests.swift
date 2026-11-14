import AppKit
import InAppSettings
import TelegramTheme
import XCTest

final class MessageBubbleTailTests: XCTestCase {
    private func tailAlpha(in image: CGImage, incoming: Bool) -> CGFloat {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let diameter = bitmap.pixelsHigh
        let tailWidth = bitmap.pixelsWide - diameter
        let columns = incoming ? 0 ..< tailWidth : diameter ..< bitmap.pixelsWide
        var result: CGFloat = 0
        for x in columns {
            for y in 0 ..< bitmap.pixelsHigh {
                result = max(result, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return result
    }

    private func pixelData(_ image: CGImage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testTailRemovalKeepsMaskDimensionsAndCapInsetsInBothDirections() throws {
        for incoming in [true, false] {
            for neighbors: MessageBubbleImageNeighbors in [.none, .bottom] {
                let (visible, visibleInsets) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbors)
                let (hidden, hiddenInsets) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbors, showsTail: false)
                let (restored, _) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbors, showsTail: true)

                XCTAssertGreaterThan(tailAlpha(in: visible, incoming: incoming), 0.5)
                XCTAssertEqual(tailAlpha(in: hidden, incoming: incoming), 0)
                XCTAssertEqual(visible.width, hidden.width)
                XCTAssertEqual(visible.height, hidden.height)
                XCTAssertEqual(visibleInsets.top, hiddenInsets.top)
                XCTAssertEqual(visibleInsets.bottom, hiddenInsets.bottom)
                XCTAssertEqual(visibleInsets.left, hiddenInsets.left)
                XCTAssertEqual(visibleInsets.right, hiddenInsets.right)
                XCTAssertTrue(restored === visible)
                XCTAssertNotEqual(try pixelData(visible), try pixelData(hidden))
            }
        }
    }

    func testUnmergedTaillessMaskUsesTheNativeRoundedCorner() throws {
        for incoming in [true, false] {
            let (hidden, _) = messageBubbleMaskImage(incoming: incoming, neighbors: .none, showsTail: false)
            let (rounded, _) = messageBubbleMaskImage(incoming: incoming, neighbors: .extracted)
            XCTAssertEqual(try pixelData(hidden), try pixelData(rounded))
        }
    }

    func testGroupsWithoutTailRetainTheSameShape() throws {
        for incoming in [true, false] {
            for neighbors: MessageBubbleImageNeighbors in [.both, .top(side: false), .top(side: true), .side, .extracted] {
                let (visible, _) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbors)
                let (hidden, _) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbors, showsTail: false)
                XCTAssertEqual(try pixelData(visible), try pixelData(hidden))
            }
        }
    }

    func testPreferenceDefaultsToTailsPersistsAndDisposesObserver() throws {
        let suite = "Gergram.MessageBubbleTail.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = MessageBubbleTailPreferences(defaults: defaults)
        var values: [Bool] = []
        let subscription = preferences.signal.start(next: { values.append($0) })
        preferences.setHidden(true)
        preferences.setHidden(true)
        XCTAssertTrue(MessageBubbleTailPreferences(defaults: defaults).isHidden)
        preferences.setHidden(false)
        subscription.dispose()
        preferences.setHidden(true)

        XCTAssertEqual(values, [false, true, false])
    }
}
