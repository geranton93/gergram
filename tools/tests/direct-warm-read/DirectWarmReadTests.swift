import Foundation
import SwiftSignalKit
import XCTest

private struct MediaResource { let path: String }
private enum Mode { case complete }

private final class MediaBox {
    struct Read: Equatable {
        let attemptsSynchronously: Bool
        let reportsIncomplete: Bool
    }

    var completed = false
    private(set) var completedChecks = 0
    private(set) var reads: [Read] = []
    private(set) var queuedReads = 0
    var deferredRead: ((Data) -> Void)?
    var delaysQueuedReads = false

    func completedResourcePath(_ resource: MediaResource) -> String? {
        completedChecks += 1
        return completed ? resource.path : nil
    }

    func resourceData(_ resource: MediaResource, size: Int64, in range: Range<Int64>, mode: Mode,
                      notifyAboutIncomplete: Bool, attemptSynchronously: Bool) -> Signal<(Data, Bool), NoError> {
        reads.append(.init(attemptsSynchronously: attemptSynchronously, reportsIncomplete: notifyAboutIncomplete))
        if attemptSynchronously, completed {
            return .single((Data(repeating: 7, count: range.count), true))
        }
        queuedReads += 1
        if delaysQueuedReads {
            return Signal { subscriber in
                self.deferredRead = { data in
                    subscriber.putNext((data, true))
                    subscriber.putCompletion()
                }
                return ActionDisposable { self.deferredRead = nil }
            }
        }
        if completed {
            return .single((Data(repeating: 7, count: range.count), true))
        }
        return notifyAboutIncomplete ? .single((Data(), false)) : .never()
    }
}

__SUBSCRIBE__

private typealias PacketRead = (Range<Int64>, Signal<Void, NoError>?, DirectMediaReadWaiter) -> Disposable

private func workerRead(mediaBox: MediaBox, mediaResource: MediaResource, resourceSize: Int64) -> PacketRead {
__READ_STATE__
    return __READ_CLOSURE__
}

final class DirectWarmReadTests: XCTestCase {
    func testCompleteFileDeterminesOnceAndAvoidsQueueForSeveralPackets() {
        let box = MediaBox()
        box.completed = true
        let read = reader(box)
        for range: Range<Int64> in [0..<128, 256..<384, 128..<256] {
            XCTAssertEqual(packet(read, range: range), .bytes(Data(repeating: 7, count: 128)))
        }
        XCTAssertEqual(box.completedChecks, 1)
        XCTAssertEqual(box.queuedReads, 0)
        XCTAssertEqual(box.reads.map(\.attemptsSynchronously), [true, true, true])
    }

    func testColdReaderStaysOnQueueAfterFileBecomesComplete() {
        let box = MediaBox()
        let read = reader(box)
        XCTAssertEqual(packet(read), .failed)
        box.completed = true
        XCTAssertEqual(packet(read), .bytes(Data(repeating: 7, count: 128)))
        XCTAssertEqual(box.completedChecks, 1)
        XCTAssertEqual(box.queuedReads, 2)
        XCTAssertEqual(box.reads.map(\.attemptsSynchronously), [false, false])
    }

    func testEvictionOfWarmFileFallsBackAndLiveFetchRetainsExistingRoute() {
        let box = MediaBox()
        box.completed = true
        let read = reader(box)
        XCTAssertEqual(packet(read), .bytes(Data(repeating: 7, count: 128)))
        box.completed = false
        XCTAssertEqual(packet(read), .failed)
        XCTAssertEqual(packet(read, fetchCompletion: .single(())), .failed)
        XCTAssertEqual(box.completedChecks, 1)
        XCTAssertEqual(box.queuedReads, 3)
        XCTAssertEqual(box.reads.map(\.attemptsSynchronously), [true, true, false, false])
        XCTAssertEqual(box.reads.map(\.reportsIncomplete), [true, true, false, true])
    }

    func testCancelledPacketsSkipOrReleaseNativeReadWork() {
        let box = MediaBox()
        let read = reader(box)
        let cancelled = DirectMediaReadWaiter()
        cancelled.cancel()
        let skipped = read(0..<128, nil, cancelled)
        XCTAssertEqual(cancelled.wait(), .cancelled)
        XCTAssertEqual(box.completedChecks, 0)
        XCTAssertTrue(box.reads.isEmpty)
        skipped.dispose()

        box.delaysQueuedReads = true
        let pending = DirectMediaReadWaiter()
        let disposable = read(0..<128, nil, pending)
        let queued = box.deferredRead
        XCTAssertNotNil(queued)
        pending.cancel()
        XCTAssertEqual(pending.wait(), .cancelled)
        disposable.dispose()
        queued?(Data(repeating: 1, count: 128))
        XCTAssertEqual(pending.wait(), .cancelled)
        XCTAssertNil(box.deferredRead)
    }

    private func reader(_ box: MediaBox) -> PacketRead {
        workerRead(mediaBox: box, mediaResource: .init(path: "/cache/video"), resourceSize: 512)
    }

    private func packet(_ read: PacketRead, range: Range<Int64> = 0..<128, fetchCompletion: Signal<Void, NoError>? = nil) -> DirectMediaReadWaiter.Outcome {
        let waiter = DirectMediaReadWaiter()
        let disposable = read(range, fetchCompletion, waiter)
        defer { disposable.dispose() }
        return waiter.wait()
    }
}
