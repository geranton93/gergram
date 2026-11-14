private final class TableResortController {
    var resortRange: NSRange
    var canContinueResorting: () -> Bool = { true }
    var requiresStableSourceRow = false
    var completeDelay = 0.4
    let start: (Int) -> Void
    let complete: (Int, Int) -> Void

    init(resortRange: NSRange, startTimeout: Double, start: @escaping (Int) -> Void, resort: (Int) -> Void, complete: @escaping (Int, Int) -> Void) {
        self.resortRange = resortRange
        self.start = start
        self.complete = complete
    }
}

private final class ReorderPreviewFixture {
    struct View {
        let tableView = Table()
        let sendButton = SendButton()
    }

    final class Table {
        var resortController: TableResortController?
    }

    final class SendButton {
        var alphaValue: Double = 1
        func shake(beep: Bool) {}
    }

    struct Journey {
        enum Failure { case preparation }
        func submissionBlocked(_ failure: Failure) {}
    }

    let genericView = View()
    let pendingActions = PreviewSenderPendingActions()
    let chatInteraction = ChatInteraction()
    var sent = false
    var appFile: Int?
    var isRenderingEdit = false
    var pendingRenderSend: (() -> Void)?
    var preparedOrder: PreviewSenderAttachmentOrder?
    var displayedAttachmentOrder: PreviewSenderAttachmentOrder?
    var analyticsMediaJourney: Journey? = Journey()
    var attachmentOrder: PreviewSenderAttachmentOrder
    private(set) var moves: [[URL]] = []

    init(_ attachmentOrder: PreviewSenderAttachmentOrder) {
        self.attachmentOrder = attachmentOrder
    }

    func getPreparedAttachmentOrder() -> PreviewSenderAttachmentOrder? { preparedOrder }
    func getMedias() -> [Int] { [] }
    func isPreviewPlaceholder(_ media: Int) -> Bool { false }
    func validateSendSource() -> Bool { true }

__SEND_ORDER__

    func bind() -> (PreviewSenderAttachmentOrder) -> Void {
__ORDER_VALIDATION__
        let arguments = (reorder: { [weak self] (order: PreviewSenderAttachmentOrder, reordered: [URL]) in
            guard let self, canReorder(order) else { return }
            self.moves.append(reordered)
        }, validate: canReorder)
__DRAG_BINDING__
        return { [weak self] order in
            self?.displayedAttachmentOrder = order
            resort.resortRange = NSRange(location: 0, length: order.rowCount)
        }
    }
}

private struct ReorderAlbumFixture {
    struct Message { let id: Int }
    struct Layout { let messages: [Message] }

    let layout: Layout
    let attachmentPositions: [Int: Int]
    let urls: [URL]

__GROUP_ATTACHMENT__
}

final class AttachmentOrderTests: XCTestCase {
    private let files = ["notes.pdf", "recording.mp3", "image.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }
    private let photos = (0..<23).map { URL(fileURLWithPath: "/tmp/\($0).jpg") }

    func testMixedFileRowsMoveWithoutChangingOtherRelativeOrder() {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        XCTAssertEqual(order.movingRows(from: 0, to: 2), [files[1], files[2], files[0]])
        XCTAssertEqual(order.movingRows(from: 2, to: 0), [files[2], files[0], files[1]])
    }

    func testInvalidAndNoOpDropsAreRejected() {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        for (from, to) in [(-1, 0), (0, -1), (3, 0), (0, 3), (Int.max, 0), (0, Int.max), (1, 1)] {
            XCTAssertNil(order.movingRows(from: from, to: to))
        }
        XCTAssertNil(order.movingItem(from: 0, to: 1, inAlbum: 0))
        let archive = order.updating(urls: files, layout: .archive)
        XCTAssertEqual(archive.rowCount, 1)
        XCTAssertNil(archive.movingRows(from: 0, to: 1))
    }

    func testAlbumTilesMoveWithinTheirOwnSlice() {
        let order = PreviewSenderAttachmentOrder(urls: photos, layout: .albums)
        var expected = photos
        let firstTileInSecondAlbum = expected.remove(at: 10)
        expected.insert(firstTileInSecondAlbum, at: 12)
        XCTAssertEqual(order.movingItem(from: 0, to: 2, inAlbum: 1), expected)
        XCTAssertEqual(order.range(forRow: 2), 20..<23)
        XCTAssertNil(order.movingItem(from: 0, to: 3, inAlbum: 2))
        XCTAssertNil(order.movingItem(from: 0, to: 1, inAlbum: 3))
    }

    func testAlbumRowsMoveAsBlocksIncludingTheShortLastAlbum() {
        let order = PreviewSenderAttachmentOrder(urls: photos, layout: .albums)
        let first = Array(photos[0..<10])
        let second = Array(photos[10..<20])
        let last = Array(photos[20..<23])
        XCTAssertEqual(order.movingRows(from: 2, to: 0), last + first + second)
        XCTAssertEqual(order.movingRows(from: 0, to: 2), second + last + first)
        XCTAssertEqual(order.movingRows(from: 1, to: 2), first + last + second)
    }

    func testAlbumTilesKeepTheirOriginalAttachmentWhenTheLayoutFiltersAMessage() throws {
        let order = PreviewSenderAttachmentOrder(urls: photos, layout: .albums)
        let messages = [21, 22].map { ReorderAlbumFixture.Message(id: $0) }
        let row = ReorderAlbumFixture(layout: .init(messages: messages), attachmentPositions: [20: 0, 21: 1, 22: 2], urls: Array(photos[20..<23]))
        XCTAssertEqual(row.attachmentURL(at: 0), photos[21])
        XCTAssertEqual(row.attachmentURL(at: 1), photos[22])
        XCTAssertNil(row.attachmentURL(at: 2))
        let from = try XCTUnwrap(row.attachmentIndex(at: 0))
        let to = try XCTUnwrap(row.attachmentIndex(at: 1))
        var expected = photos
        expected.swapAt(21, 22)
        XCTAssertEqual(order.movingItem(from: from, to: to, inAlbum: 2), expected)
    }

    func testUnchangedSnapshotKeepsRevisionAndReturningToSameOrderGetsNewRevision() {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        XCTAssertEqual(order.updating(urls: files, layout: .items), order)
        let reversed = order.updating(urls: Array(files.reversed()), layout: .items)
        XCTAssertNotEqual(reversed.updating(urls: files, layout: .items), order)
        XCTAssertNotEqual(order.updating(urls: files, layout: .albums), order)
    }

    func testDragUsesDisplayedSnapshotAndCompletesSynchronously() throws {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        let preview = ReorderPreviewFixture(order)
        let display = preview.bind()
        let resort = try XCTUnwrap(preview.genericView.tableView.resortController)
        display(order)
        resort.start(0)

        XCTAssertTrue(resort.canContinueResorting())
        XCTAssertTrue(resort.requiresStableSourceRow)
        XCTAssertEqual(resort.completeDelay, 0)
        resort.complete(0, 2)
        resort.complete(3, 1)
        XCTAssertEqual(preview.moves, [[files[1], files[2], files[0]]])
    }

    func testDragRejectsNewSelectionBeforeAndAfterItsRowsAreDisplayed() throws {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        let preview = ReorderPreviewFixture(order)
        let display = preview.bind()
        let resort = try XCTUnwrap(preview.genericView.tableView.resortController)
        display(order)
        resort.start(0)
        let smaller = order.updating(urls: Array(files.dropFirst()), layout: .items)
        preview.attachmentOrder = smaller
        XCTAssertFalse(resort.canContinueResorting())
        resort.complete(0, 2)
        display(smaller)
        XCTAssertFalse(resort.canContinueResorting())
        resort.complete(0, 1)
        XCTAssertTrue(preview.moves.isEmpty)

        resort.start(0)
        XCTAssertTrue(resort.canContinueResorting())
        resort.complete(0, 1)
        XCTAssertEqual(preview.moves, [[files[2], files[1]]])
    }

    func testDragRejectsRebuiltIdenticalOrderAndClosedPreview() throws {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        let preview = ReorderPreviewFixture(order)
        let display = preview.bind()
        let resort = try XCTUnwrap(preview.genericView.tableView.resortController)
        display(order)
        resort.start(0)
        let regrouped = order.updating(urls: files, layout: .albums).updating(urls: files, layout: .items)
        preview.attachmentOrder = regrouped
        display(regrouped)
        XCTAssertFalse(resort.canContinueResorting())
        resort.complete(0, 2)
        resort.start(0)
        XCTAssertTrue(resort.canContinueResorting())
        preview.pendingActions.close()
        XCTAssertFalse(resort.canContinueResorting())
        resort.complete(0, 2)
        XCTAssertTrue(preview.moves.isEmpty)
    }

    func testSendRequiresCurrentPreparedAndDisplayedRevisionWithoutQueuingStaleOrder() {
        let original = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        let reordered = original.updating(urls: Array(files.reversed()), layout: .items)
        let preview = ReorderPreviewFixture(reordered)
        preview.displayedAttachmentOrder = original
        var replayed = false
        let replay = { replayed = true }

        XCTAssertFalse(preview.canSendPreparedAttachments(original, afterRendering: replay))
        XCTAssertFalse(preview.canSendPreparedAttachments(reordered, afterRendering: replay))
        XCTAssertNil(preview.pendingRenderSend)
        preview.displayedAttachmentOrder = reordered
        XCTAssertFalse(preview.canSendPreparedAttachments(original, afterRendering: replay))
        XCTAssertTrue(preview.canSendPreparedAttachments(reordered, afterRendering: replay))
        preview.preparedOrder = reordered
        preview.flushPendingRenderSend()
        XCTAssertFalse(replayed)

        preview.appFile = 1
        XCTAssertTrue(preview.canSendPreparedAttachments(nil, afterRendering: replay))
    }

    func testExistingRenderSendResumesOnlyInItsOriginalComposeSource() {
        let order = PreviewSenderAttachmentOrder(urls: files, layout: .items)
        let preview = ReorderPreviewFixture(order)
        preview.displayedAttachmentOrder = order
        preview.preparedOrder = order
        var sends = 0

        preview.isRenderingEdit = true
        XCTAssertFalse(preview.canSendPreparedAttachments(order) { sends += 1 })
        preview.chatInteraction.revision += 1
        preview.isRenderingEdit = false
        preview.flushPendingRenderSend()
        XCTAssertEqual(sends, 0)

        preview.isRenderingEdit = true
        XCTAssertFalse(preview.canSendPreparedAttachments(order) { sends += 1 })
        preview.isRenderingEdit = false
        preview.flushPendingRenderSend()
        preview.flushPendingRenderSend()
        XCTAssertEqual(sends, 1)
    }
}
