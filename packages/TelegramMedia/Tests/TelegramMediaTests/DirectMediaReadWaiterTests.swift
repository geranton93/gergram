import Foundation
import XCTest
@testable import TelegramMedia

final class DirectMediaReadWaiterTests: XCTestCase {
    func testCompletionWithoutBytesReleasesABlockedRead() {
        let waiter = DirectMediaReadWaiter()
        let completed = expectation(description: "Read completed")

        DispatchQueue.global().async {
            XCTAssertEqual(waiter.wait(), .failed)
            completed.fulfill()
        }
        waiter.receive(nil)
        wait(for: [completed], timeout: 2)
    }

    func testCompletionAfterDataDoesNotDiscardBytes() {
        let waiter = DirectMediaReadWaiter()
        let bytes = Data([0x01, 0x02])

        waiter.receive(bytes)
        waiter.receive(nil)
        XCTAssertEqual(waiter.wait(), .bytes(bytes))
    }

    func testCancellationWinsOverLateData() {
        let waiter = DirectMediaReadWaiter()

        waiter.cancel()
        waiter.receive(Data([0x01]))
        XCTAssertEqual(waiter.wait(), .cancelled)
    }

    func testEmptyReadRemainsACompletedByteResult() {
        let waiter = DirectMediaReadWaiter()

        waiter.receive(Data())
        waiter.receive(nil)
        XCTAssertEqual(waiter.wait(), .bytes(Data()))
    }

    func testFetchFinishingWithoutTheRequestedBytesReleasesTheRead() {
        let waiter = DirectMediaReadWaiter()
        let completed = expectation(description: "Read completed")

        DispatchQueue.global().async {
            XCTAssertEqual(waiter.wait(), .failed)
            completed.fulfill()
        }
        waiter.fetchFinished(requestedBytesOnDisk: false)
        wait(for: [completed], timeout: 2)
    }

    func testAvailableBytesStillReachReaderAfterFetchFinishes() {
        let waiter = DirectMediaReadWaiter()
        let bytes = Data([0x01, 0x02])

        waiter.fetchFinished(requestedBytesOnDisk: true)
        waiter.receive(bytes)
        XCTAssertEqual(waiter.wait(), .bytes(bytes))
    }
}
