import AppKit
import InAppSettings
import TelegramTheme
import TGUIKit
import XCTest

final class MessageBubbleRadiusTests: XCTestCase {
    private func alpha(in image: CGImage, x: Int, y: Int) -> CGFloat {
        NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private func containsTail(_ image: CGImage, incoming: Bool) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let columns = incoming ? 0 ..< image.width - image.height : image.height ..< image.width
        return columns.contains { x in
            (0 ..< image.height).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5
            }
        }
    }

    func testRadiusScalesTheOuterAndJoinedMediaCornersInBothDirections() {
        let expected = ImageCorners(topLeft: .Corner(7), topRight: .Corner(3), bottomLeft: .Corner(7), bottomRight: .Corner(3))
        let mirrored = ImageCorners(topLeft: .Corner(3), topRight: .Corner(7), bottomLeft: .Corner(3), bottomRight: .Corner(7))
        XCTAssertEqual(messageBubbleCorners(incoming: false, neighbors: .both, inset: 1, radius: 8), expected)
        XCTAssertEqual(messageBubbleCorners(incoming: true, neighbors: .both, inset: 1, radius: 8), mirrored)
        XCTAssertEqual(messageBubbleCorners(incoming: false, neighbors: .top(side: true), inset: 0, radius: 9),
                       ImageCorners(topLeft: .Corner(9), topRight: .Corner(9), bottomLeft: .Corner(5), bottomRight: .Corner(5)))
        XCTAssertEqual(messageBubbleCorners(incoming: true, neighbors: .none, inset: 1, radius: 0), ImageCorners())
    }

    func testSquareAndRoundedMasksHaveDistinctPixelsAndKeepTheSameSliceGeometry() {
        for incoming in [false, true] {
            let (rounded, roundedInsets) = messageBubbleMaskImage(incoming: incoming, neighbors: .none, showsTail: false)
            let (square, squareInsets) = messageBubbleMaskImage(incoming: incoming, neighbors: .none, showsTail: false, radius: 0)
            let (restored, _) = messageBubbleMaskImage(incoming: incoming, neighbors: .none, showsTail: false, radius: 16)
            let x = incoming ? square.width - square.height : 0

            XCTAssertEqual(alpha(in: square, x: x, y: 0), 1)
            XCTAssertEqual(alpha(in: rounded, x: x, y: 0), 0)
            XCTAssertEqual(square.width, rounded.width)
            XCTAssertEqual(square.height, rounded.height)
            XCTAssertTrue(NSEdgeInsetsEqual(squareInsets, roundedInsets))
            XCTAssertTrue(restored === rounded)
        }
    }

    func testTailVisibilityAndGroupedOwnershipAtEveryRadius() {
        for incoming in [false, true] {
            for radius in MessageBubbleRadiusPreferences.allowedRadii {
                for neighbor: MessageBubbleImageNeighbors in [.none, .bottom] {
                    let (visible, _) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbor, radius: radius)
                    let (hidden, _) = messageBubbleMaskImage(incoming: incoming, neighbors: neighbor, showsTail: false, radius: radius)
                    XCTAssertTrue(containsTail(visible, incoming: incoming))
                    XCTAssertFalse(containsTail(hidden, incoming: incoming))
                }
                let (joined, _) = messageBubbleMaskImage(incoming: incoming, neighbors: .both, radius: radius)
                XCTAssertFalse(containsTail(joined, incoming: incoming))
            }
        }
    }

    func testOutOfRangeRendererInputsShareTheClampedCacheEntry() {
        let (minimum, _) = messageBubbleMaskImage(incoming: false, neighbors: .none, radius: 0)
        let (underflow, _) = messageBubbleMaskImage(incoming: false, neighbors: .none, radius: .min)
        let (maximum, _) = messageBubbleMaskImage(incoming: true, neighbors: .none, radius: 16)
        let (overflow, _) = messageBubbleMaskImage(incoming: true, neighbors: .none, radius: .max)

        XCTAssertTrue(minimum === underflow)
        XCTAssertTrue(maximum === overflow)
    }

    func testPreferencePersistsZeroAndRejectsInvalidValues() throws {
        let suite = "Gergram.MessageBubbleRadius.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = MessageBubbleRadiusPreferences(defaults: defaults)
        var values: [Int] = []
        let subscription = preferences.signal.start(next: { values.append($0) })
        preferences.setRadius(0)
        preferences.setRadius(0)
        preferences.setRadius(-1)
        preferences.setRadius(17)
        XCTAssertEqual(MessageBubbleRadiusPreferences(defaults: defaults).radius, 0)
        preferences.setRadius(8)
        subscription.dispose()
        preferences.setRadius(16)

        XCTAssertEqual(values, [16, 0, 8])
        defaults.set(100, forKey: "Gergram.Chat.MessageBubbleRadius")
        XCTAssertEqual(MessageBubbleRadiusPreferences(defaults: defaults).radius, 16)
    }
}
