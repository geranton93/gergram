import Foundation
import SwiftSignalKit
import XCTest

struct ResourceID: Equatable { let stringRepresentation: String }
struct Resource: Equatable {
    let id: ResourceID
    init(_ name: String) { id = ResourceID(stringRepresentation: name) }
}
public struct TelegramApplicationIcons: Equatable {
    public struct Icon: Equatable {
        struct File: Equatable {
            let fileName: String?
            let resource: Resource
        }
        let file: File
        let reference: Int
        static let defaultIconName = "Default.icns"
        init(_ name: String, resource: String, reference: Int = 1) {
            file = .init(fileName: name, resource: Resource(resource))
            self.reference = reference
        }
    }
    let icons: [Icon]
}
struct ResourceData { let complete: Bool; let path: String }
final class MediaBox {
    private(set) var fetchStarts: [String] = []
    private(set) var fetchStops: [String] = []
    private(set) var observations: [String] = []
    private(set) var observationStops: [String] = []
    private var resources: [String: ValuePipe<ResourceData>] = [:]

    func fetch(_ resource: Resource) -> Signal<Void, NoError> {
        let id = resource.id.stringRepresentation
        return Signal { [weak self] _ in
            self?.fetchStarts.append(id)
            return ActionDisposable { [weak self] in self?.fetchStops.append(id) }
        }
    }
    func resourceData(_ resource: Resource) -> Signal<ResourceData, NoError> {
        let id = resource.id.stringRepresentation
        let pipe = resources[id] ?? ValuePipe<ResourceData>()
        resources[id] = pipe
        return Signal { [weak self] subscriber in
            self?.observations.append(id)
            let disposable = pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in
                self?.observationStops.append(id)
                disposable.dispose()
            }
        }
    }
    func publish(_ id: String, complete: Bool = true) {
        resources[id]?.putNext(.init(complete: complete, path: "/icons/\(id)"))
    }
}
public final class TelegramEngine {
    final class Resources {
        let catalog = ValuePipe<TelegramApplicationIcons>()
        func applicationIcons() -> Signal<TelegramApplicationIcons, NoError> { catalog.signal() }
    }
    struct Account { let postbox = Postbox() }
    struct Postbox { let mediaBox = MediaBox() }
    let resources = Resources()
    let account = Account()
}
public enum TelegramAccountManagerTypes {}
struct DockSettings: Equatable { let iconSelected: String? }
public final class AccountManager<T> {
    let settings = ValuePromise(DockSettings(iconSelected: nil), ignoreRepeated: true)
}
func dockSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<DockSettings, NoError> {
    accountManager.settings.get()
}
enum AnyMediaReference { case message(message: Int, media: TelegramApplicationIcons.Icon.File) }
enum MediaResourceReference { case media(media: AnyMediaReference, resource: Resource) }
enum FetchMode { case other }
func fetchedMediaResource(mediaBox: MediaBox, userLocation: FetchMode, userContentType: FetchMode, reference: MediaResourceReference) -> Signal<Void, NoError> {
    switch reference {
    case let .media(_, resource): mediaBox.fetch(resource)
    }
}
enum Dock {
    static var applied: [String?] = []
    static func setCustomAppIcon(path: String?) { applied.append(path) }
}

final class DockControlTests: XCTestCase {
    private let bundled = TelegramApplicationIcons.Icon("Default.icns", resource: "bundled")
    private let a = TelegramApplicationIcons.Icon("A.icns", resource: "a")
    private let b = TelegramApplicationIcons.Icon("B.icns", resource: "b")
    private let c = TelegramApplicationIcons.Icon("C.icns", resource: "c")

    override func setUp() {
        super.setUp()
        Dock.applied = []
    }

    func testCatalogReusesCurrentFetchesAndDisposesOnlyRemovedResources() {
        let engine = TelegramEngine()
        let settings = AccountManager<TelegramAccountManagerTypes>()
        let control = DockControl(engine, accountManager: settings)
        let box = engine.account.postbox.mediaBox
        let aAlias = TelegramApplicationIcons.Icon("AAlias.icns", resource: "a")
        var catalogs: [TelegramApplicationIcons] = []
        let observed = control.icons.start(next: { catalogs.append($0) })
        publish([bundled, a, aAlias, b], engine)
        publish([bundled, a, aAlias, b], engine)
        publish([b, a], engine)
        publish([b, c], engine)
        XCTAssertEqual(box.fetchStarts, ["a", "b", "c"])
        XCTAssertEqual(box.fetchStops, ["a"])
        XCTAssertEqual(catalogs.count, 3)
        control.clear()
        control.clear()
        publish([a], engine)
        XCTAssertEqual(Set(box.fetchStops), ["a", "b", "c"])
        XCTAssertEqual(box.fetchStops.count, 3)
        XCTAssertEqual(catalogs.count, 3)
        observed.dispose()
    }

    func testUnrelatedCatalogChangesKeepSelectedResourcePendingAndApplyOnlyCompleteData() {
        let engine = TelegramEngine()
        let settings = AccountManager<TelegramAccountManagerTypes>()
        let control = DockControl(engine, accountManager: settings)
        let box = engine.account.postbox.mediaBox
        settings.settings.set(.init(iconSelected: "A.icns"))
        publish([a, b], engine)
        box.publish("a", complete: false)
        publish([a, c], engine)
        XCTAssertEqual(box.observations, ["a"])
        XCTAssertTrue(box.observationStops.isEmpty)
        XCTAssertTrue(Dock.applied.isEmpty)
        box.publish("a")
        box.publish("a")
        XCTAssertEqual(Dock.applied, ["/icons/a"])
        XCTAssertEqual(box.observationStops, ["a"])
        control.clear()
    }

    func testSwitchAndResetRejectLateResourceCompletions() {
        let engine = TelegramEngine()
        let settings = AccountManager<TelegramAccountManagerTypes>()
        let control = DockControl(engine, accountManager: settings)
        let box = engine.account.postbox.mediaBox
        publish([bundled, a, b], engine)
        XCTAssertEqual(Dock.applied, [nil])
        settings.settings.set(.init(iconSelected: "A.icns"))
        settings.settings.set(.init(iconSelected: "B.icns"))
        box.publish("a")
        box.publish("b")
        settings.settings.set(.init(iconSelected: "A.icns"))
        settings.settings.set(.init(iconSelected: "Default.icns"))
        box.publish("a")
        settings.settings.set(.init(iconSelected: nil))
        XCTAssertEqual(Dock.applied, [nil, "/icons/b", nil])
        control.clear()
    }

    func testQueuedCompletionForRetiredSelectionCannotUpdateDock() {
        let engine = TelegramEngine()
        let settings = AccountManager<TelegramAccountManagerTypes>()
        let control = DockControl(engine, accountManager: settings)
        let box = engine.account.postbox.mediaBox
        settings.settings.set(.init(iconSelected: "A.icns"))
        publish([a, b], engine)
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.publish("a")
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        settings.settings.set(.init(iconSelected: "B.icns"))
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        box.publish("b")
        XCTAssertEqual(Dock.applied, ["/icons/b"])
        control.clear()
    }

    func testChangingSelectedResourceAndDeinitRetireOldSubscriptions() {
        let engine = TelegramEngine()
        let settings = AccountManager<TelegramAccountManagerTypes>()
        let box = engine.account.postbox.mediaBox
        var control: DockControl? = DockControl(engine, accountManager: settings)
        let remaining = { [weak control] in control }
        settings.settings.set(.init(iconSelected: "A.icns"))
        publish([a, b], engine)
        let replacement = TelegramApplicationIcons.Icon("A.icns", resource: "updated-a")
        publish([replacement, b], engine)
        box.publish("a")
        XCTAssertEqual(box.observations, ["a", "updated-a"])
        XCTAssertTrue(Dock.applied.isEmpty)
        control = nil
        XCTAssertNil(remaining())
        box.publish("updated-a")
        XCTAssertTrue(Dock.applied.isEmpty)
        XCTAssertEqual(Set(box.fetchStops), ["a", "updated-a", "b"])
        XCTAssertEqual(box.observationStops, ["a", "updated-a"])
    }

    private func publish(_ icons: [TelegramApplicationIcons.Icon], _ engine: TelegramEngine) {
        engine.resources.catalog.putNext(.init(icons: icons))
    }
}
