import Postbox
import XCTest
@testable import ChatUI

final class ChatBulkDeleteSelectionTests: XCTestCase {
    private typealias Selection = ChatBulkDeleteSelection

    private let author = PeerId(10)
    private let peer = PeerId(20)
    private let otherPeer = PeerId(21)
    private let thread: Int64 = 30

    private var scope: Selection.Scope {
        .init(accountId: 1, authorId: author, peerId: peer, threadId: thread)
    }

    private func id(_ value: Int32, peer: PeerId? = nil) -> MessageId {
        .init(peerId: peer ?? self.peer, namespace: 0, id: value)
    }

    private func candidate(
        _ value: Int32, peer: PeerId? = nil, mine: Bool = true, thread: Int64? = 30,
        timestamp: Int32 = 200, version: UInt32 = 1, media: Set<Selection.MediaFilter> = []
    ) -> Selection.Candidate {
        .init(id: id(value, peer: peer), authorId: mine ? author : otherPeer, threadId: thread,
              timestamp: timestamp, version: version, media: media)
    }

    private func ready(_ result: Selection.Result, file: StaticString = #filePath, line: UInt = #line) throws -> Selection.Preview {
        guard case let .ready(preview) = result else {
            XCTFail("Expected a preview", file: file, line: line)
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        return preview
    }

    func testOnlyExplicitAccountAuthorPeerAndTopicCanMatch() throws {
        let messages = [candidate(1), candidate(2, peer: otherPeer), candidate(3, mine: false),
                        candidate(4, thread: 31), candidate(5, thread: nil)]
        let preview = try ready(Selection.preview(scope: scope, dates: nil, media: .all, candidates: messages))
        XCTAssertEqual(preview.ids, [id(1)])

        let directScope = Selection.Scope(accountId: 1, authorId: author, peerId: peer, threadId: nil)
        let direct = try ready(Selection.preview(scope: directScope, dates: nil, media: .all, candidates: messages))
        XCTAssertEqual(direct.ids, [id(5)])
    }

    func testDateBoundariesAndMediaFiltersOnlyIncludeMatchingIDs() throws {
        let messages = [candidate(1, timestamp: 99, media: [.photos]), candidate(2, timestamp: 100, media: [.photos]),
                        candidate(3, timestamp: 200, media: [.photos]), candidate(4, timestamp: 201, media: [.photos]),
                        candidate(5, timestamp: 150, media: [.videos]), candidate(6, timestamp: 150, media: [.gifs]),
                        candidate(7, timestamp: 150, media: [.videoMessages]), candidate(8, timestamp: 150, media: [.voice]),
                        candidate(9, timestamp: 150, media: [.stickers]), candidate(10, timestamp: 150)]
        let expected: [Selection.MediaFilter: Set<MessageId>] = [
            .photos: [id(2), id(3)], .videos: [id(5)], .gifs: [id(6)],
            .videoMessages: [id(7)], .voice: [id(8)], .stickers: [id(9)],
            .all: Set([2, 3, 5, 6, 7, 8, 9, 10].map { id($0) })
        ]
        for (filter, ids) in expected {
            let preview = try ready(Selection.preview(scope: scope, dates: 100...200, media: filter, candidates: messages))
            XCTAssertEqual(preview.ids, ids)
        }
        XCTAssertNil(Selection.DateFilter.all.range(endingAt: 0))
        XCTAssertEqual(Selection.DateFilter.pastWeek.range(endingAt: 0), -604_800...0)
        XCTAssertEqual(Selection.DateFilter.pastMonth.range(endingAt: Int32.min), (Int64(Int32.min) - 2_592_000)...Int64(Int32.min))
    }

    func testDuplicatesDoNotInflatePreviewAndConflictingVersionsAreRejected() throws {
        let message = candidate(1)
        let preview = try ready(Selection.preview(scope: scope, dates: nil, media: .all, candidates: [message, message]))
        XCTAssertEqual(preview.ids, [id(1)])
        XCTAssertEqual(Selection.preview(scope: scope, dates: nil, media: .all,
                                         candidates: [message, candidate(1, version: 2)]), .changed)
    }

    func testPreviewAndScanCapsNeverSelectAPartialResult() throws {
        let atLimit = (1...Int32(Selection.limit)).map { candidate($0) }
        let preview = try ready(Selection.preview(scope: scope, dates: nil, media: .all, candidates: atLimit))
        XCTAssertEqual(preview.ids.count, Selection.limit)
        XCTAssertEqual(Selection.preview(scope: scope, dates: nil, media: .all,
                                         candidates: atLimit + [candidate(Int32(Selection.limit + 1))]), .limitExceeded)
        XCTAssertEqual(Selection.preview(scope: scope, dates: nil, media: .all,
                                         candidates: Array(repeating: candidate(1), count: Selection.scanLimit + 1)), .scanLimitExceeded)
        XCTAssertEqual(Selection.preview(scope: scope, dates: nil, media: .all, candidates: []), .empty)
    }

    func testConfirmationUsesOnlyFrozenMatchingIDs() throws {
        let first = candidate(1, media: [.photos])
        let second = candidate(2, media: [.photos])
        let preview = try ready(Selection.preview(scope: scope, dates: 100...200, media: .photos, candidates: [first, second]))

        XCTAssertEqual(preview.confirmedIds(in: scope, candidates: [second, first, candidate(3, media: [.photos])]), [id(1), id(2)])
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, version: 2, media: [.photos])]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, media: [.videos])]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, timestamp: 201, media: [.photos])]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, thread: 31, media: [.photos])]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, mine: false, media: [.photos])]))
        XCTAssertNil(preview.confirmedIds(in: scope, candidates: [first, candidate(2, peer: otherPeer, media: [.photos])]))

        for changed in [
            Selection.Scope(accountId: 2, authorId: author, peerId: peer, threadId: thread),
            .init(accountId: 1, authorId: otherPeer, peerId: peer, threadId: thread),
            .init(accountId: 1, authorId: author, peerId: otherPeer, threadId: thread),
            .init(accountId: 1, authorId: author, peerId: peer, threadId: thread + 1)
        ] {
            XCTAssertNil(preview.confirmedIds(in: changed, candidates: [first, second]))
        }
    }
}
