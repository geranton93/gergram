import AppKit
import XCTest

private typealias AppKitView = AppKit.NSView

public protocol Disposable {
    func dispose()
}

final class ActionDisposable: Disposable {
    private var block: (() -> Void)?
    init(_ block: @escaping () -> Void) { self.block = block }
    func dispose() {
        let block = self.block
        self.block = nil
        block?()
    }
}

final class MetaDisposable: Disposable {
    private var value: Disposable?
    func set(_ value: Disposable?) {
        self.value?.dispose()
        self.value = value
    }
    func dispose() { set(nil) }
}

enum NoValue {}
enum NoError {}
enum TestQueue {
    static func mainQueue() -> TestQueue { .main }
    case main
}

final class Signal<Value, Failure> {
    private static var pending: [Scheduled] {
        get { TestTimer.pending }
        set { TestTimer.pending = newValue }
    }

    static func complete() -> Signal { Signal() }
    func start(completed: @escaping () -> Void) -> Disposable {
        let scheduled = Scheduled(completed)
        Self.pending.append(scheduled)
        return ActionDisposable { scheduled.block = nil }
    }
}

final class Scheduled {
    var block: (() -> Void)?
    init(_ block: @escaping () -> Void) { self.block = block }
}

enum TestTimer {
    static var pending: [Scheduled] = []
    static func fire() {
        let timers = pending
        pending.removeAll()
        timers.forEach { $0.block?() }
    }
}

func delay<T, E>(_ duration: Double, queue: TestQueue) -> (Signal<T, E>) -> Signal<T, E> { { $0 } }
infix operator |>: AdditionPrecedence
func |> <T, R>(value: T, pipe: (T) -> R) -> R { pipe(value) }

class NSEvent {
    struct ModifierFlags: OptionSet {
        let rawValue: Int
        static let control = ModifierFlags(rawValue: 1)
    }
    static var pressedMouseButtons = 1
    let locationInWindow: CGPoint
    let window: NSWindow?
    let clickCount: Int
    let modifierFlags: ModifierFlags

    init(_ point: CGPoint, window: NSWindow?, clickCount: Int = 1, modifierFlags: ModifierFlags = []) {
        locationInWindow = point
        self.window = window
        self.clickCount = clickCount
        self.modifierFlags = modifierFlags
    }
}

public class NSWindow {
    var mouseLocationOutsideOfEventStream = CGPoint.zero
    var isKeyWindow = true
}

public final class Window: NSWindow {}

public class NSView {
    var frame = CGRect.zero
    var subviews: [NSView] = []
}

public enum QuickPreviewMedia {
    case file(Media, Any.Type)
}

final class GifPreviewModalView {}
final class AnimatedStickerPreviewModalView {}
final class StickerPreviewModalView {}

public struct Media {
    let id: Int
    var stickerReference: Int? { nil }
    var isAnimatedSticker: Bool { false }
    var isWebm: Bool { false }
}

typealias FileMediaReference = Media

extension Media {
    static func stickerPack(stickerPack: Int, media: Media) -> Media { media }
    static func standalone(media: Media) -> Media { media }
}

enum Entry {
    case gif(Int, Media)
    case sticker(Int, Media)
    case photo
}

struct MediaRow {
    let entries: [Entry]
    let results: [Int]
    let messages: [Int]
}

final class Arguments {
    var sendResult: (Int?, Int, NSView) -> Void = { _, _, _ in }
    var openMessage: (Int) -> Void = { _ in }
    var beginDrag: ((Int, NSPoint) -> (update: (NSPoint, Bool) -> Void, cancel: () -> Void)?)?
}

class TableRowItem {}
final class ContextMediaRowItem: TableRowItem {
    let result: MediaRow
    let arguments = Arguments()
    let context = TestAccountContext()
    let collection: Int? = nil
    let table: TestTable?

    init(_ id: Int, table: TestTable?, photo: Bool = false, message: Bool = false) {
        let entries: [Entry] = photo ? [.photo, .photo] : [.gif(id, Media(id: id)), .gif(id + 1, Media(id: id + 1))]
        result = MediaRow(entries: entries, results: message ? [] : [id, id + 1], messages: message ? [id, id + 1] : [])
        self.table = table
    }
}

public protocol ModalPreviewProtocol: AnyObject {
    func fileAtLocationInWindow(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)?
}

public protocol AccountContextProtocol {}
struct TestAccountContext: AccountContextProtocol {}

final class TestTable: ModalPreviewProtocol {
    weak var window: Window?
    var previews: [Int] = []
    var dismissed = 0
    var lookups = 0
    var lookup: ((NSPoint) -> (QuickPreviewMedia, NSView?)?)?

    func fileAtLocationInWindow(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        lookups += 1
        return lookup?(point)
    }
}

private var activePreviewHandler: ModalPreviewHandler?

private final class ModalPreviewHandler {
    private weak var table: TestTable?

    init(_ global: ModalPreviewProtocol, window: Window, context: any AccountContextProtocol) {
        table = global as? TestTable
    }

    func startHandler(initial: (QuickPreviewMedia, NSView?)) {
        if case let .file(media, _) = initial.0 { table?.previews.append(media.id) }
    }

    func stopHandler() {
        guard activePreviewHandler === self else { return }
        activePreviewHandler = nil
        table?.dismissed += 1
    }
}

__PREVIEW_ENTRY__

class TableRowView: NSView {
    var window: NSWindow?
    var item: TableRowItem?
    var visibleRect = CGRect(x: 0, y: 0, width: 200, height: 100)
    var isHiddenOrHasHiddenAncestor = false
    var superForceClicks = 0
    var windowOrigin = CGPoint(x: 270, y: 435)

    func convert(_ point: NSPoint, from: NSView?) -> NSPoint {
        CGPoint(x: point.x - windowOrigin.x, y: point.y - windowOrigin.y)
    }
    func convert(_ point: NSPoint, to: NSView?) -> NSPoint {
        CGPoint(x: point.x + windowOrigin.x, y: point.y + windowOrigin.y)
    }
    func mouseInside() -> Bool {
        guard let window else { return false }
        return visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    func mouseDown(with event: NSEvent) {}
    func mouseDragged(with event: NSEvent) {}
    func mouseUp(with event: NSEvent) {}
    func forceClick(in location: NSPoint) { superForceClicks += 1 }
    func set(item: TableRowItem, animated: Bool) { self.item = item }
    func viewWillMove(toWindow: NSWindow?) {}
}

final class ContextMediaRowView: TableRowView {
__PREVIEW__
__REBIND__
__GESTURE__
}

struct CanvasPick {
    let image: Int
}

enum CanvasDrag: Equatable {
    case moved(Int?, NSPoint)
    case preview(Int)
    case ended
    case dropped(Int, NSPoint)
}

enum CanvasDragPhase {
    case moved(NSPoint)
    case ended(NSPoint)
}

typealias CGImage = Int

final class CanvasInteractions {
    var dragItem: ((Int, CGImage?, CanvasDragPhase) -> Void)?
    var cancelItemDrag: (() -> Void)?
    var imageCanvasPickerOwner: UUID?
    var retireImageCanvasPicker: (() -> Void)?
    var sendSticker: (Int, Int, Int, Int) -> Void = { _, _, _, _ in }
    var sendAnimatedEmoji: (Int, Int, Int, Int, Int) -> Void = { _, _, _, _, _ in }
    var sendEmoji: (Int, Int) -> Void = { _, _ in }
    var sendGIF: (Int, Int, Int) -> Void = { _, _, _ in }
}

typealias EntertainmentInteractions = CanvasInteractions

final class CanvasEntertainment {
    var interactions: CanvasInteractions? = CanvasInteractions()
    var closes = 0
    func closePopover() { closes += 1 }
}

final class CanvasPicker {
    let entertainment: CanvasEntertainment
    let disposable = MetaDisposable()
    let dragDisposable = MetaDisposable()
    weak var pickerInteractions: EntertainmentInteractions?
    var pickerOwner: UUID?
    var stopAcceptingDrags: (() -> Void)?
    var dropDisposable: MetaDisposable?
    var visibilityChanged: ((Bool) -> Void)?
    var events: [CanvasDrag] = []
    var requested: [Int] = []
    var disposed: [Int] = []
    var callbacks: [(CanvasPick) -> Void] = []

    init(entertainment: CanvasEntertainment = CanvasEntertainment()) {
        self.entertainment = entertainment
    }

    deinit { releasePickerOwnership() }

    func show() {
        guard let interactions = entertainment.interactions else { return }
        invalidateDragRoutes(preservingDrop: false)
        disposable.set(nil)
        let owner = claimPickerOwnership(on: interactions)
        let drag = { [weak self] (event: CanvasEvent) in
            guard let self else { return }
            switch event {
            case let .moved(image, point): events.append(.moved(image, point))
            case let .preview(pick): events.append(.preview(pick.image))
            case .ended: events.append(.ended)
            case let .dropped(pick, point): events.append(.dropped(pick.image, point))
            }
        }
__CANVAS_SHOW__
    }

__CANVAS_VISIBILITY__
__CANVAS_TEARDOWN__

    func hide() { updatePickerVisibility(false) }

    enum CanvasEvent {
        case moved(CGImage?, NSPoint)
        case preview(CanvasPick)
        case ended
        case dropped(CanvasPick, NSPoint)
    }

    func pick(_ id: Int, disposable: MetaDisposable, select: @escaping (CanvasPick) -> Void) {
        requested.append(id)
        callbacks.append(select)
        disposable.set(ActionDisposable { [weak self] in self?.disposed.append(id) })
    }
}

final class ContextMediaPreviewTests: XCTestCase {
    private let first = CGPoint(x: 290, y: 460)
    private let second = CGPoint(x: 400, y: 460)
    private let outside = CGPoint(x: 500, y: 460)
    private var row = ContextMediaRowView()
    private var window = Window()
    private var table = TestTable()
    private var sent: [Int] = []

    override func setUp() {
        super.setUp()
        TestTimer.pending.removeAll()
        NSEvent.pressedMouseButtons = 1
        row = ContextMediaRowView()
        window = Window()
        table = TestTable()
        table.window = window
        row.window = window
        for x in [0, 100] {
            let tile = NSView()
            tile.frame = CGRect(x: x, y: 0, width: 100, height: 100)
            row.subviews.append(tile)
        }
        table.lookup = { [weak row] point in
            guard let row else { return nil }
            return row.fileAtPoint(row.convert(point, from: nil))
        }
        bind(10)
    }

    @discardableResult
    private func bind(_ id: Int, photo: Bool = false, message: Bool = false) -> ContextMediaRowItem {
        let item = ContextMediaRowItem(id, table: table, photo: photo, message: message)
        item.arguments.sendResult = { [weak self] _, id, _ in self?.sent.append(id) }
        item.arguments.openMessage = { [weak self] id in self?.sent.append(id) }
        row.set(item: item, animated: false)
        return item
    }

    private func down(_ point: CGPoint) {
        window.mouseLocationOutsideOfEventStream = point
        row.mouseDown(with: NSEvent(point, window: window))
    }

    private func drag(_ point: CGPoint) {
        window.mouseLocationOutsideOfEventStream = point
        row.mouseDragged(with: NSEvent(point, window: window))
    }

    private func up(_ point: CGPoint) {
        window.mouseLocationOutsideOfEventStream = point
        row.mouseUp(with: NSEvent(point, window: window))
    }

    @objc func testOffsetRowPreviewsOriginalTileWithoutRecomputingWindowHit() {
        table.lookup = { _ in (.file(Media(id: 99), GifPreviewModalView.self), nil) }
        down(first)
        TestTimer.fire()
        XCTAssertEqual(table.previews, [10])
        XCTAssertEqual(table.lookups, 0)
        up(second)
        XCTAssertEqual(sent, [])
    }

    @objc func testHoverAndOutsidePressCannotPreviewAnotherTile() {
        window.mouseLocationOutsideOfEventStream = first
        TestTimer.fire()
        XCTAssertEqual(table.previews, [])
        down(outside)
        window.mouseLocationOutsideOfEventStream = first
        TestTimer.fire()
        up(first)
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [])
    }

    @objc func testRowRebindCancelsPendingPreviewAndRelease() {
        down(first)
        bind(20)
        TestTimer.fire()
        up(first)
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [])
        down(first)
        up(first)
        TestTimer.fire()
        XCTAssertEqual(sent, [20])
    }

    @objc func testDetachmentClosesActivePreviewAndClearsPress() {
        down(first)
        TestTimer.fire()
        XCTAssertEqual(table.previews, [10])
        row.viewWillMove(toWindow: nil)
        row.window = nil
        row.window = window
        up(first)
        XCTAssertEqual(table.dismissed, 1)
        XCTAssertEqual(sent, [])
    }

    @objc func testMovingBetweenTilesCannotPreviewOrReleaseIntoNewTile() {
        down(first)
        drag(second)
        TestTimer.fire()
        up(second)
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [])
    }

    @objc func testCanvasDragFinishesWithOriginalResultAfterRowRebind() {
        var dragged: [Int] = []
        var phases: [Bool] = []
        bind(10).arguments.beginDrag = { id, _ in
            dragged.append(id)
            phases.append(false)
            return (update: { _, ended in
                dragged.append(id)
                phases.append(ended)
            }, cancel: {
                XCTFail("Rebinding within the window preserves an explicit canvas drag")
            })
        }
        down(first)
        drag(second)
        bind(20).arguments.beginDrag = { _, _ in
            XCTFail("Rebound row must not start a drag for the stale press")
            return nil
        }
        TestTimer.fire()
        up(second)
        XCTAssertEqual(dragged, [10, 10])
        XCTAssertEqual(phases, [false, true])
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [])
    }

    @objc func testNativePhotoClickAndSharedMessageClickStillWork() {
        bind(10, photo: true)
        down(first)
        TestTimer.fire()
        up(first)
        bind(20, message: true)
        down(second)
        up(second)
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [10, 21])
    }

    @objc func testForceClickDoesNotPreviewOutsideRowOrSendAfterSuccessfulPreview() {
        down(outside)
        row.forceClick(in: row.convert(outside, from: nil))
        XCTAssertEqual(row.superForceClicks, 1)
        down(second)
        window.mouseLocationOutsideOfEventStream = first
        row.forceClick(in: row.convert(second, from: nil))
        TestTimer.fire()
        up(second)
        XCTAssertEqual(table.previews, [11])
        XCTAssertEqual(sent, [])
    }

    @objc func testLegacyPreviewEntryStillReadsWindowHitAndRejectsNonKeyWindow() {
        window.mouseLocationOutsideOfEventStream = first
        let handle = startModalPreviewHandle(table, window: window, context: TestAccountContext())
        XCTAssertEqual(table.previews, [10])
        XCTAssertEqual(table.lookups, 1)
        handle?.dispose()
        XCTAssertEqual(table.dismissed, 1)

        window.isKeyWindow = false
        down(second)
        TestTimer.fire()
        XCTAssertNil(startModalPreviewHandle(table, window: window, context: TestAccountContext()))
        XCTAssertEqual(table.previews, [10])
        XCTAssertEqual(table.lookups, 1)
    }

    @objc func testClippedOrReplacedTilesCannotTriggerPreviewOrRelease() {
        down(second)
        row.visibleRect.size.width = 100
        TestTimer.fire()
        up(second)
        row.visibleRect.size.width = 200
        down(second)
        let replacement = NSView()
        replacement.frame = row.subviews[1].frame
        row.subviews[1] = replacement
        TestTimer.fire()
        up(second)
        XCTAssertEqual(table.previews, [])
        XCTAssertEqual(sent, [])
    }

    @objc func testDetachmentDoesNotConvertCanvasDragIntoDropOrClick() {
        var phases: [Bool] = []
        var cancellations = 0
        bind(10).arguments.beginDrag = { _, _ in
            phases.append(false)
            return (update: { _, ended in phases.append(ended) }, cancel: { cancellations += 1 })
        }
        down(first)
        drag(second)
        row.viewWillMove(toWindow: nil)
        row.window = nil
        row.window = window
        up(second)
        XCTAssertEqual(phases, [false])
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(sent, [])
    }

    @objc func testCanvasCancelDisposesPreviewAndDoesNotPickOrDrop() throws {
        let picker = CanvasPicker()
        picker.show()
        let interactions = try XCTUnwrap(picker.entertainment.interactions)
        interactions.dragItem?(10, nil, .moved(first))
        interactions.cancelItemDrag?()
        interactions.cancelItemDrag?()
        picker.callbacks[0](CanvasPick(image: 10))
        interactions.dragItem?(10, nil, .ended(second))
        XCTAssertEqual(picker.requested, [10])
        XCTAssertEqual(picker.disposed, [10])
        XCTAssertEqual(picker.events, [.moved(nil, first), .ended])
    }

    @objc func testCanvasAcceptsFreshDragAndIgnoresOldPreviewAfterCancellation() throws {
        let picker = CanvasPicker()
        picker.show()
        let interactions = try XCTUnwrap(picker.entertainment.interactions)
        interactions.dragItem?(10, nil, .moved(first))
        interactions.cancelItemDrag?()
        interactions.dragItem?(20, nil, .moved(second))
        picker.callbacks[0](CanvasPick(image: 10))
        picker.callbacks[1](CanvasPick(image: 20))
        interactions.dragItem?(20, nil, .ended(first))
        picker.callbacks[2](CanvasPick(image: 20))
        XCTAssertEqual(picker.requested, [10, 20, 20])
        XCTAssertEqual(picker.events, [.moved(nil, first), .ended, .moved(nil, second),
                                      .preview(20), .ended, .dropped(20, first)])
    }

    @objc func testCanvasReopenInvalidatesDelayedDropAndOldRoute() throws {
        let picker = CanvasPicker()
        picker.show()
        let interactions = try XCTUnwrap(picker.entertainment.interactions)
        let oldDrag = try XCTUnwrap(interactions.dragItem)
        oldDrag(10, nil, .moved(first))
        oldDrag(10, nil, .ended(second))
        picker.show()
        picker.callbacks[1](CanvasPick(image: 10))
        oldDrag(10, nil, .moved(first))
        XCTAssertEqual(picker.requested, [10, 10])
        XCTAssertEqual(picker.events, [.moved(nil, first), .ended])
    }

    @objc func testCanvasVisibilityLossCancelsOngoingDragAndPreservesAcceptedDrop() throws {
        let picker = CanvasPicker()
        picker.show()
        let interactions = try XCTUnwrap(picker.entertainment.interactions)
        let oldDrag = try XCTUnwrap(interactions.dragItem)
        oldDrag(10, nil, .moved(first))
        picker.hide()
        picker.callbacks[0](CanvasPick(image: 10))
        oldDrag(10, nil, .ended(second))
        XCTAssertNil(interactions.dragItem)
        XCTAssertNil(interactions.cancelItemDrag)
        XCTAssertEqual(picker.requested, [10])
        XCTAssertEqual(picker.disposed, [10])

        picker.show()
        interactions.dragItem?(20, nil, .moved(first))
        interactions.dragItem?(20, nil, .ended(second))
        picker.hide()
        picker.callbacks[2](CanvasPick(image: 20))
        picker.callbacks[2](CanvasPick(image: 20))
        XCTAssertEqual(picker.disposed, [10, 20, 20])
        XCTAssertEqual(picker.events, [.moved(nil, first), .ended, .moved(nil, first), .ended, .dropped(20, second)])
    }

    @objc func testReplacingCanvasOwnerRejectsItsOldDelayedDrop() throws {
        let shared = CanvasEntertainment()
        let firstPicker = CanvasPicker(entertainment: shared)
        let secondPicker = CanvasPicker(entertainment: shared)
        let interactions = try XCTUnwrap(shared.interactions)
        firstPicker.show()
        let oldDrag = try XCTUnwrap(interactions.dragItem)
        oldDrag(10, nil, .moved(first))
        oldDrag(10, nil, .ended(second))
        secondPicker.show()
        firstPicker.callbacks[1](CanvasPick(image: 10))
        oldDrag(10, nil, .moved(first))
        XCTAssertEqual(firstPicker.requested, [10, 10])
        XCTAssertEqual(firstPicker.disposed, [10, 10])
        XCTAssertEqual(firstPicker.events, [.moved(nil, first), .ended])
    }

    @objc func testLateCloseFromFirstCanvasPreservesSecondOwnerRoutes() throws {
        let shared = CanvasEntertainment()
        let firstPicker = CanvasPicker(entertainment: shared)
        let secondPicker = CanvasPicker(entertainment: shared)
        let interactions = try XCTUnwrap(shared.interactions)
        firstPicker.show()
        interactions.dragItem?(10, nil, .moved(first))
        secondPicker.show()
        let closesAfterReplacement = shared.closes
        firstPicker.close()
        XCTAssertEqual(shared.closes, closesAfterReplacement)
        XCTAssertNotNil(interactions.cancelItemDrag)
        interactions.dragItem?(20, nil, .moved(second))
        XCTAssertEqual(firstPicker.disposed, [10])
        XCTAssertEqual(firstPicker.events, [.moved(nil, first), .ended])
        XCTAssertEqual(secondPicker.requested, [20])
    }

    @objc func testDeinitializingDisplacedCanvasDoesNotClearSecondOwnersRoutes() throws {
        let shared = CanvasEntertainment()
        var firstPicker: CanvasPicker? = CanvasPicker(entertainment: shared)
        weak let retiredPicker = firstPicker
        let secondPicker = CanvasPicker(entertainment: shared)
        let interactions = try XCTUnwrap(shared.interactions)
        firstPicker?.show()
        secondPicker.show()
        firstPicker = nil
        XCTAssertNil(retiredPicker)
        XCTAssertNotNil(interactions.cancelItemDrag)
        interactions.dragItem?(20, nil, .moved(second))
        XCTAssertEqual(secondPicker.requested, [20])
    }

    @objc func testAppKitConversionOfOffsetRowFromWindowCoordinates() {
        let parent = AppKitView(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        let offsetRow = AppKitView(frame: CGRect(x: 270, y: 435, width: 200, height: 100))
        parent.addSubview(offsetRow)
        let firstTile = CGRect(x: 0, y: 0, width: 100, height: 100)
        let local = offsetRow.convert(first, from: parent)
        XCTAssertTrue(firstTile.contains(local))
        XCTAssertEqual(local, CGPoint(x: 20, y: 25))
        XCTAssertFalse(firstTile.contains(offsetRow.convert(first, to: parent)))
    }
}

let suite = XCTestSuite(forTestCaseClass: ContextMediaPreviewTests.self)
suite.run()
exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
