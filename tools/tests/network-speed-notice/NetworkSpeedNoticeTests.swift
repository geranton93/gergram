import AppKit
import SwiftSignalKit
import XCTest

struct PeerId: Hashable {
    struct Id: Hashable {
        let value: Int64
        static func _internalFromInt64Value(_ value: Int64) -> Self { Self(value: value) }
    }
    let namespace: Int32
    let id: Id
}

struct MessageId: Hashable {
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}

enum Namespaces {
    enum Peer {
        static let CloudUser: Int32 = 0
    }
    enum Message {
        static let Cloud: Int32 = 0
    }
}

struct MediaResourceId: Equatable {
    let rawValue: Int64
}

struct LocalFileMediaResource {
    let fileId: Int64
    var id: MediaResourceId { .init(rawValue: fileId) }
}

protocol Media {}

struct TelegramMediaFile: Media {
    let resource: LocalFileMediaResource
}

struct TelegramMediaImage: Media {
    struct Representation {
        let resource: LocalFileMediaResource
    }
    let representations: [Representation]
    let videoRepresentations: [Representation]
    let video: TelegramMediaFile?
}

enum NetworkSpeedLimitedEvent {
    public enum DownloadSubject {
        case message(MessageId)
    }
    case upload
    case download(DownloadSubject)
}

__CORE_STATE__

final class Network: NSObject {
__CORE_PIPE__
__CORE_PUBLICATION__
}

private final class PendingPart {}

private final class FetchingState {
    var pendingParts: [PendingPart] = []
}

private final class FetchFixture {
    struct Parameters {
        struct Location {
            let messageId: MessageId?
        }
        let location: Location?
    }

    let network = Network()
    let queue = Queue.mainQueue()
    var resource = LocalFileMediaResource(fileId: 1)
    var current: FetchingState?
    var parameters: Parameters?

    func isCurrent(_ state: FetchingState) -> Bool { current === state }

    func callback(state: FetchingState, part: PendingPart) -> (String) -> Void {
        let resourceId = resource.id
        let queue = self.queue
        return callback(onFloodWaitError:
__FLOOD_CALLBACK__
        )
    }

    private func callback(onFloodWaitError: @escaping (String) -> Void) -> (String) -> Void { onFloodWaitError }

__FLOOD_EVENT__
}

private final class ChatMessage {
    let id: MessageId
    var containsSecretMedia = false
    var isMediaSpoilered = false
    init(_ id: MessageId) { self.id = id }
}

private final class ChatMediaContentView: NSView {
    struct Parameters {
        let isProtected: Bool
    }
    var parent: ChatMessage?
    var media: Media?
    var parameters: Parameters?
}

private final class ChatGroupedView: NSView {
    var contents: [ChatMediaContentView] = []
}

private final class ChatMediaView: NSView {
    var contentNode: ChatMediaContentView?
}

private final class ChatRowItem {
    let view: NSView?
    init(view: NSView?) { self.view = view }
}

private final class ChatTable {
    var rows: [ChatRowItem] = []
    func enumerateVisibleItems(with callback: (Any) -> Bool) {
        for row in rows {
            if !callback(row) { break }
        }
    }
}

private final class ChatFixture {
    class Window: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isVisible: Bool { true }
    }
    struct Configuration {
        func getGeneralValueDouble(_ key: String, orElse fallback: Double) -> Double { fallback }
    }
    final class Context {
        let window: NSWindow
        var isCurrent = true
        var isExternal = false
        var isFrozen = false
        var isPremium = false
        let appConfiguration = Configuration()
        let account: Account

        init(window: NSWindow, network: Network) {
            self.window = window
            self.account = Account(network: network)
        }
    }
    struct Account {
        let network: Network
    }
    struct GenericView {
        let tableView = ChatTable()
        var window: NSWindow?
        var isHiddenOrHasHiddenAncestor: Bool { false }
    }
    struct Interaction {
        let peerId = PeerId(namespace: 0, id: .init(value: 1))
    }
    struct Navigation {
        weak var controller: ChatFixture?
    }
    let context: Context
    let chatInteraction = Interaction()
    let genericView: GenericView
    lazy var navigationController: Navigation? = Navigation(controller: self)
    var isAnalyticsVisible = true
    var presents: [ChatNetworkSpeedNotice.Download] = []

    init(network: Network = Network()) {
        let window = Window(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
        context = Context(window: window, network: network)
        genericView = GenericView(window: window)
    }

    func presentNetworkSpeedNotice(download: ChatNetworkSpeedNotice.Download?) {
        if let download { presents.append(download) }
    }

__CONTROLLER_NOTICE__
}

private enum ChatUIHooks {
    struct Hooks {
        func appIsLockedValue() -> Bool? { false }
    }
    static let shared = Hooks()
}

private func hasModals(_ window: NSWindow?) -> Bool { false }

final class NetworkSpeedNoticeTests: XCTestCase {
    private func message(_ id: Int32) -> MessageId {
        MessageId(peerId: PeerId(namespace: 0, id: .init(value: 1)), namespace: 0, id: id)
    }

    private func visibleTile(_ message: ChatMessage, resource: Int64) -> ChatMediaContentView {
        let tile = ChatMediaContentView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        tile.parent = message
        tile.media = TelegramMediaFile(resource: .init(fileId: resource))
        return tile
    }

    func testPinnedCoreKeepsLegacySignalAndCarriesExactActivePartResource() {
        let fetch = FetchFixture()
        let message = message(2)
        fetch.parameters = .init(location: .init(messageId: message))
        let part = PendingPart()
        let state = FetchingState()
        state.pendingParts = [part]
        fetch.current = state
        var legacyEvents = 0
        var downloadEvents: [ChatNetworkSpeedNotice.Download] = []
        let legacy = fetch.network.networkSpeedLimitedEvents.start(next: { _ in legacyEvents += 1 })
        let detailed = fetch.network.networkSpeedLimitedEventsWithResource.start(next: { event in
            if let download = ChatNetworkSpeedNotice.Download(event: event.event, resourceId: event.downloadResourceId) {
                downloadEvents.append(download)
            }
        })
        defer {
            legacy.dispose()
            detailed.dispose()
        }

        let callback = fetch.callback(state: state, part: part)
        callback("FLOOD_WAIT_2")
        XCTAssertEqual(legacyEvents, 0)
        fetch.parameters = .init(location: .init(messageId: nil))
        callback("FLOOD_PREMIUM_WAIT_10")
        XCTAssertEqual(legacyEvents, 0)
        fetch.parameters = .init(location: .init(messageId: message))
        callback("FLOOD_PREMIUM_WAIT_10")
        XCTAssertEqual(downloadEvents, [.init(messageId: message, resourceId: fetch.resource.id)])
        XCTAssertEqual(legacyEvents, 1)

        fetch.resource = .init(fileId: 3)
        callback("FLOOD_PREMIUM_WAIT_10")
        fetch.resource = .init(fileId: 1)
        state.pendingParts = []
        callback("FLOOD_PREMIUM_WAIT_10")
        state.pendingParts = [part]
        fetch.current = FetchingState()
        callback("FLOOD_PREMIUM_WAIT_10")
        XCTAssertEqual(legacyEvents, 1)

        fetch.network.addNetworkSpeedLimitedEvent(event: .upload)
        fetch.network.addNetworkSpeedLimitedEvent(event: .download(.message(message)))
        XCTAssertEqual(legacyEvents, 3)
        XCTAssertEqual(downloadEvents.count, 1)
        fetch.network.markNetworkSpeedLimitDisplayed()
        fetch.current = state
        callback("FLOOD_PREMIUM_WAIT_10")
        XCTAssertEqual(legacyEvents, 3)
    }

    func testRenderedAlbumRequiresVisibleOriginatingTileAndUnchangedResource() {
        let fixture = ChatFixture()
        let album = ChatGroupedView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let expected = visibleTile(ChatMessage(message(1)), resource: 4)
        let unrelated = visibleTile(ChatMessage(message(2)), resource: 4)
        album.contents = [unrelated, expected]
        album.addSubview(unrelated)
        album.addSubview(expected)
        fixture.context.window.contentView?.addSubview(album)
        fixture.genericView.tableView.rows = [ChatRowItem(view: album)]
        let download = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: .init(rawValue: 4))
        expected.isHidden = true
        XCTAssertNil(fixture.visibleDownloadSpeedNotice(in: [download]))
        expected.isHidden = false
        XCTAssertEqual(fixture.visibleDownloadSpeedNotice(in: [download]), download)
        expected.media = TelegramMediaFile(resource: .init(fileId: 5))
        XCTAssertNil(fixture.visibleDownloadSpeedNotice(in: [download]))
        expected.media = TelegramMediaFile(resource: .init(fileId: 4))
        expected.parameters = .init(isProtected: true)
        XCTAssertNil(fixture.visibleDownloadSpeedNotice(in: [download]))
    }

    func testPhotoAndItsNonPrimaryVideoResourcesMatchOnlyTheOriginatingMedia() {
        let fixture = ChatFixture()
        let row = ChatMediaView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let tile = visibleTile(ChatMessage(message(1)), resource: 0)
        tile.media = TelegramMediaImage(
            representations: [.init(resource: .init(fileId: 4)), .init(resource: .init(fileId: 5))],
            videoRepresentations: [.init(resource: .init(fileId: 6))],
            video: .init(resource: .init(fileId: 7))
        )
        row.contentNode = tile
        row.addSubview(tile)
        fixture.context.window.contentView?.addSubview(row)
        fixture.genericView.tableView.rows = [ChatRowItem(view: NSView(frame: row.frame)), ChatRowItem(view: row)]
        for id in 4 ... 7 {
            let download = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: .init(rawValue: Int64(id)))
            XCTAssertEqual(fixture.visibleDownloadSpeedNotice(in: [download]), download)
        }
        let unrelated = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: .init(rawValue: 8))
        XCTAssertNil(fixture.visibleDownloadSpeedNotice(in: [unrelated]))
        tile.parent?.isMediaSpoilered = true
        let concealed = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: .init(rawValue: 5))
        XCTAssertNil(fixture.visibleDownloadSpeedNotice(in: [concealed]))
    }

    func testReceiveSharesPendingOriginButInactiveAccountClearsIt() {
        let network = Network()
        let first = ChatFixture(network: network)
        let second = ChatFixture(network: network)
        let source = message(1)
        let resourceId = MediaResourceId(rawValue: 7)
        let event = NetworkSpeedLimitedEvent.download(.message(source))
        first.receiveNetworkSpeedNotice(event, downloadResourceId: resourceId)
        second.receiveNetworkSpeedNotice(event, downloadResourceId: resourceId)
        first.receiveNetworkSpeedNotice(.download(.message(message(2))), downloadResourceId: nil)
        XCTAssertEqual(ChatNetworkSpeedNotice.shared.pendingDownloads(network: network), [.init(messageId: source, resourceId: resourceId)])
        XCTAssertTrue(first.presents.isEmpty)
        XCTAssertTrue(second.presents.isEmpty)
        first.context.isCurrent = false
        first.replayDownloadSpeedNotice()
        XCTAssertTrue(ChatNetworkSpeedNotice.shared.pendingDownloads(network: network).isEmpty)
    }

    func testDeferredDownloadPresentsOnceWhenExactTileBecomesVisible() {
        let fixture = ChatFixture()
        let source = message(1)
        let resourceId = MediaResourceId(rawValue: 7)
        let download = ChatNetworkSpeedNotice.Download(messageId: source, resourceId: resourceId)
        let event = NetworkSpeedLimitedEvent.download(.message(source))
        let row = ChatMediaView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let tile = visibleTile(ChatMessage(source), resource: 7)
        row.contentNode = tile
        row.addSubview(tile)
        fixture.context.window.contentView?.addSubview(row)
        fixture.genericView.tableView.rows = [ChatRowItem(view: row)]
        tile.isHidden = true
        fixture.receiveNetworkSpeedNotice(event, downloadResourceId: resourceId)
        XCTAssertTrue(fixture.presents.isEmpty)
        tile.isHidden = false
        fixture.replayDownloadSpeedNotice()
        fixture.receiveNetworkSpeedNotice(event, downloadResourceId: resourceId)
        fixture.replayDownloadSpeedNotice()
        XCTAssertEqual(fixture.presents, [download])
        XCTAssertTrue(ChatNetworkSpeedNotice.shared.pendingDownloads(network: fixture.context.account.network).isEmpty)
    }
}
