import Foundation
import Darwin
import XCTest
@testable import TelegramMedia

final class DirectMediaReadLifecycleTests: XCTestCase {
    func testSeekResolvesAllFFmpegOffsetModes() {
        XCTAssertEqual(DirectMediaReadPosition.seek(offset: 12, whence: SEEK_SET, current: 50, fileSize: 100), 12)
        XCTAssertEqual(DirectMediaReadPosition.seek(offset: -12, whence: SEEK_CUR, current: 50, fileSize: 100), 38)
        XCTAssertEqual(DirectMediaReadPosition.seek(offset: -12, whence: SEEK_END, current: 50, fileSize: 100), 88)
        XCTAssertEqual(DirectMediaReadPosition.seek(offset: 0, whence: SEEK_END | 0x20000, current: 50, fileSize: 100), 100)
    }

    func testSeekRejectsInvalidPositionsAndModes() {
        XCTAssertNil(DirectMediaReadPosition.seek(offset: -1, whence: SEEK_SET, current: 50, fileSize: 100))
        XCTAssertNil(DirectMediaReadPosition.seek(offset: 51, whence: SEEK_CUR, current: 50, fileSize: 100))
        XCTAssertNil(DirectMediaReadPosition.seek(offset: Int64.max, whence: SEEK_END, current: 50, fileSize: 100))
        XCTAssertNil(DirectMediaReadPosition.seek(offset: 12, whence: 3, current: 50, fileSize: 100))
    }

    func testPendingTimestampReplacesObsoleteWorkAndRearmsOnTake() {
        let demand = DirectMediaReadDemand()
        XCTAssertNil(demand.take())
        XCTAssertTrue(demand.submit(0))
        for timestamp in 1 ... 10_000 {
            XCTAssertFalse(demand.submit(Double(timestamp)))
        }
        XCTAssertEqual(demand.take(), 10_000)
        XCTAssertNil(demand.take())
        XCTAssertTrue(demand.submit(10_001))
        XCTAssertEqual(demand.take(), 10_001)
    }

    func testConcurrentProducersScheduleOneWakeup() {
        let demand = DirectMediaReadDemand()
        let wakeups = expectation(description: "one timestamp wakeup")
        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            if demand.submit(Double(index)) {
                wakeups.fulfill()
            }
        }
        wait(for: [wakeups], timeout: 1)
        XCTAssertNotNil(demand.take())
        XCTAssertNil(demand.take())
    }
}
