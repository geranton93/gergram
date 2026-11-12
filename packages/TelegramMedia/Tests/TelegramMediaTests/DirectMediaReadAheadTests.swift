import XCTest
@testable import TelegramMedia

final class DirectMediaReadAheadTests: XCTestCase {
    func testSequentialReadsReuseTheWindowAndThenMoveItsStartForward() throws {
        let fileSize = Int64(64 * 1024 * 1024)
        var window = DirectMediaReadAhead.window(at: 0, fileSize: fileSize, current: nil, isCached: { _ in false })
        XCTAssertEqual(window, 0 ..< 2_097_152)

        let reused = DirectMediaReadAhead.window(at: 65_536, fileSize: fileSize, current: window, isCached: { _ in
            XCTFail("The active window already covers this read")
            return false
        })
        XCTAssertEqual(reused, window)

        var replacements = 0
        for offset in stride(from: Int64(65_536), to: fileSize, by: 65_536) {
            let next = try XCTUnwrap(DirectMediaReadAhead.window(at: offset, fileSize: fileSize, current: window, isCached: { _ in false }))
            if next != window {
                replacements += 1
                XCTAssertEqual(next.lowerBound, offset)
            }
            XCTAssertLessThanOrEqual(next.count, 2_097_152)
            XCTAssertLessThanOrEqual(next.upperBound, fileSize)
            window = next
        }
        XCTAssertGreaterThan(replacements, 0)
        XCTAssertLessThan(replacements, 64)
    }

    func testDistantSeekReplacesStaleWindowAndCachedSeekDropsIt() {
        let current = Int64(0) ..< 2_097_152
        let offset: Int64 = 32_000_000
        let fileSize: Int64 = 64_000_000

        let uncached = DirectMediaReadAhead.window(at: offset, fileSize: fileSize, current: current, isCached: { _ in false })
        XCTAssertEqual(uncached, 32_000_000 ..< 34_097_152)
        XCTAssertNil(DirectMediaReadAhead.window(at: offset, fileSize: fileSize, current: current, isCached: { _ in true }))
    }

    func testCachedProbeKeepsAnOverlappingWindow() {
        let current = Int64(0) ..< 2_097_152
        let next = DirectMediaReadAhead.window(at: 2_000_000, fileSize: 8_000_000, current: current, isCached: { probe in
            XCTAssertEqual(probe, 2_000_000 ..< 2_524_288)
            return true
        })
        XCTAssertEqual(next, current)
    }

    func testFetchAndReadRangesAreClampedAtEOFWithoutOverflow() {
        let fileSize = Int64.max
        let offset = fileSize - 8
        let window = DirectMediaReadAhead.window(at: offset, fileSize: fileSize, current: nil, isCached: { probe in
            XCTAssertEqual(probe, offset ..< fileSize)
            return false
        })
        XCTAssertEqual(window, offset ..< fileSize)
        XCTAssertEqual(DirectMediaReadAhead.boundedRange(at: offset, length: 65_536, fileSize: fileSize), offset ..< fileSize)
        XCTAssertNil(DirectMediaReadAhead.boundedRange(at: -1, length: 65_536, fileSize: fileSize))
        XCTAssertNil(DirectMediaReadAhead.boundedRange(at: 0, length: 0, fileSize: fileSize))
        XCTAssertNil(DirectMediaReadAhead.boundedRange(at: 0, length: 65_536, fileSize: 0))
        XCTAssertNil(DirectMediaReadAhead.window(at: fileSize, fileSize: fileSize, current: window, isCached: { _ in
            XCTFail("EOF must not probe the cache")
            return false
        }))
    }
}
