import XCTest
@testable import StoriesUI

final class StoryVideoPreloadRangeTests: XCTestCase {
    func testAdvertisedPrefixIsHonoredAndClippedToFileSize() {
        XCTAssertEqual(StoryVideoPreloadRange.prefix(advertisedBytes: 1_000_000, fileSize: 8_000_000), 0 ..< 1_000_000)
        XCTAssertEqual(StoryVideoPreloadRange.prefix(advertisedBytes: 1_000_000, fileSize: 700_000), 0 ..< 700_000)
    }

    func testSpeculationWithoutMetadataUsesABoundedPrefix() {
        XCTAssertEqual(StoryVideoPreloadRange.prefix(advertisedBytes: nil, fileSize: nil, allowFallback: true), 0 ..< 524_288)
        XCTAssertEqual(StoryVideoPreloadRange.prefix(advertisedBytes: 0, fileSize: 8_000_000, allowFallback: true), 0 ..< 524_288)
        XCTAssertEqual(StoryVideoPreloadRange.prefix(advertisedBytes: -1, fileSize: 200_000, allowFallback: true), 0 ..< 200_000)
    }

    func testForegroundDoesNotWaitForASpeculativePrefix() {
        XCTAssertNil(StoryVideoPreloadRange.prefix(advertisedBytes: nil, fileSize: 8_000_000))
        XCTAssertNil(StoryVideoPreloadRange.prefix(advertisedBytes: 0, fileSize: nil))
    }

    func testEmptyResourceDoesNotProduceAnEmptyFetch() {
        XCTAssertNil(StoryVideoPreloadRange.prefix(advertisedBytes: 1_000_000, fileSize: 0, allowFallback: true))
    }
}
