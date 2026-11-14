import Foundation
import InAppSettings
import SwiftSignalKit
import XCTest

private struct LocalArchiveMessage {
    enum Kind: Int { case deletion = 1, edit }
    struct Peer {
        func toInt64() -> Int64 { 100 }
    }
    struct MessageId {
        let peerId = Peer()
        let namespace = 0
        let id = 1
    }
    struct ID: Equatable {
        let message = MessageId()
        let threadId: Int64? = nil
        let kind: Kind
        let revision = 0

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind }
    }
}

private func localizedString(_ key: String) -> String {
    switch key {
    case "Gergram.Archive.Edited": "Previous Version"
    case "Gergram.Archive.Deleted": "Deleted Message"
    case "Gergram.Archive.DeletedKindWithMark": "%1$@ · %2$@"
    default: key
    }
}

__ARCHIVE_ENTRY__

private final class Window {
    var isVisible = true
    var hasModal = false
}
private func hasModals(_ window: Window) -> Bool { window.hasModal }
private final class NavigationViewController {
    weak var controller: InputDataController?
    private(set) var pushed: [InputDataController] = []
    func push(_ controller: InputDataController) { pushed.append(controller) }
}
private protocol AccountContextProtocol: AnyObject {
    var isCurrent: Bool { get }
    var isFrozen: Bool { get }
    var window: Window { get }
}
private final class AccountContext: AccountContextProtocol {
    var isCurrent = true
    var isFrozen = false
    let window = Window()
}
private struct InputDataIdentifier: Hashable {
    let value: String
    init(_ value: String) { self.value = value }
}
private enum InputDataValue {
    case string(String)
    var stringValue: String? {
        switch self {
        case let .string(value): value
        }
    }
}
private enum InputDataEntry {
    enum SectionType { case normal }
    enum Mode { case plain }
    enum ViewType { case singleItem, textBottomItem }
    enum Error { case none }
    struct RowData { let viewType: ViewType }
    enum Text { case plain(String) }
    case sectionId(Int32, type: SectionType)
    case input(sectionId: Int32, index: Int32, value: InputDataValue, error: Error?, identifier: InputDataIdentifier, mode: Mode, data: RowData, placeholder: String?, inputPlaceholder: String, filter: (String) -> String, limit: Int32)
    case desc(sectionId: Int32, index: Int32, text: Text, data: RowData)
}
private struct InputDataSignalValue { let entries: [InputDataEntry] }
private enum Validation: Equatable {
    enum Success: Equatable { case navigationBack }
    enum Error: Equatable { case alert(String) }
    case none, success(Success), fail(Error)
}
private final class InputDataController {
    weak var navigationController: NavigationViewController?
    weak var window: Window?
    var validateData: ([InputDataIdentifier: InputDataValue]) -> Validation = { _ in .none }
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {}
}

__ARCHIVE_EDITOR__

private final class ArchiveEditorSource {
    enum Scope { case account, chat }
    var scope: Scope = .account
    weak var context: (any AccountContextProtocol)?
    weak var archiveController: InputDataController?
__OPEN_EDITOR__
}

final class ArchiveDeletedMarkTests: XCTestCase {
    func testDefaultAndBlankResetAreVisibleAndPersisted() throws {
        try withPreferences { preferences, defaults in
            XCTAssertEqual(preferences.mark, "🧹")
            XCTAssertTrue(preferences.setCustomMark("  removed  "))
            XCTAssertEqual(ArchiveDeletedMarkPreferences(defaults: defaults).mark, "removed")
            XCTAssertTrue(preferences.setCustomMark("  "))
            XCTAssertEqual(preferences.mark, "🧹")
            XCTAssertEqual(ArchiveDeletedMarkPreferences(defaults: defaults).mark, "🧹")
        }
    }

    func testInvalidMarksDoNotReplaceAnExistingMark() throws {
        try withPreferences { preferences, defaults in
            XCTAssertTrue(preferences.setCustomMark("👩🏽‍💻 removed"))
            for invalid in ["two\nlines", "direction\u{202E}", "\u{200D}", String(repeating: "x", count: 17), String(repeating: "👩🏽‍💻", count: 7)] {
                XCTAssertFalse(preferences.setCustomMark(invalid))
                XCTAssertEqual(preferences.mark, "👩🏽‍💻 removed")
            }
            defaults.set("broken\nmark", forKey: "Gergram.Archive.DeletedMark")
            XCTAssertEqual(ArchiveDeletedMarkPreferences(defaults: defaults).mark, "🧹")
        }
    }

    func testOnlyEffectiveMarkChangesArePublished() throws {
        try withPreferences { preferences, _ in
            var changes: [String] = []
            let disposable = preferences.signal.start(next: { changes.append($0) })
            XCTAssertTrue(preferences.setCustomMark("🧹"))
            XCTAssertTrue(preferences.setCustomMark("tag"))
            XCTAssertTrue(preferences.setCustomMark(" tag "))
            XCTAssertFalse(preferences.setCustomMark("\ntag"))
            XCTAssertTrue(preferences.setCustomMark(""))
            disposable.dispose()
            XCTAssertTrue(preferences.setCustomMark("new tag"))
            XCTAssertEqual(changes, ["🧹", "tag", "🧹"])
        }
    }

    func testArchiveDisclosureAndMessageBodyAreIndependentOfMark() {
        let deletion = ArchiveEntry(id: .init(kind: .deletion), capturedAt: 1, chatTitle: "Chat", timestamp: 1, text: "Original message")
        let edit = ArchiveEntry(id: .init(kind: .edit), capturedAt: 1, chatTitle: "Chat", timestamp: 1, text: "Earlier message")
        XCTAssertEqual(deletion.displayKindTitle(deletedMark: "x"), "Deleted Message · x")
        XCTAssertEqual(edit.displayKindTitle(deletedMark: "x"), "Previous Version")
        XCTAssertEqual(deletion.text, "Original message")
        XCTAssertEqual(edit.text, "Earlier message")
    }

    func testEditorRequiresVisibleCurrentUnfrozenOwnerAndExplicitValidValue() throws {
        try withPreferences { preferences, _ in
            let context = AccountContext()
            let navigation = NavigationViewController()
            let editor = archiveDeletedMarkController(context: context, preferences: preferences)
            let identifier = InputDataIdentifier("deleted-mark-text")
            let value: [InputDataIdentifier: InputDataValue] = [identifier: .string("removed")]
            let original = preferences.mark
            XCTAssertEqual(editor.validateData(value), .none)
            editor.navigationController = navigation
            editor.window = context.window
            navigation.controller = editor
            context.isCurrent = false
            XCTAssertEqual(editor.validateData(value), .none)
            context.isCurrent = true
            context.isFrozen = true
            XCTAssertEqual(editor.validateData(value), .none)
            context.isFrozen = false
            context.window.isVisible = false
            XCTAssertEqual(editor.validateData(value), .none)
            context.window.isVisible = true
            context.window.hasModal = true
            XCTAssertEqual(editor.validateData(value), .none)
            context.window.hasModal = false
            XCTAssertEqual(editor.validateData([:]), .none)
            XCTAssertEqual(editor.validateData([identifier: .string("line\nbreak")]), .fail(.alert("Gergram.Archive.InvalidDeletedMark")))
            XCTAssertEqual(preferences.mark, original)
            XCTAssertEqual(editor.validateData(value), .success(.navigationBack))
            XCTAssertEqual(preferences.mark, "removed")
        }
    }

    func testEditorOpensOnlyFromVisibleTopAccountArchiveWithoutModal() {
        let context = AccountContext()
        let model = ArchiveEditorSource()
        model.context = context
        let navigation = NavigationViewController()
        let archive = InputDataController(dataSignal: .single(.init(entries: [])), title: "Archive")
        model.editDeletedMark()
        model.archiveController = archive
        model.editDeletedMark()
        archive.navigationController = navigation
        navigation.controller = archive
        model.editDeletedMark()
        archive.window = context.window
        context.window.hasModal = true
        model.editDeletedMark()
        context.window.hasModal = false
        context.window.isVisible = false
        model.editDeletedMark()
        context.window.isVisible = true
        model.scope = .chat
        model.editDeletedMark()
        XCTAssertTrue(navigation.pushed.isEmpty)
        model.scope = .account
        model.editDeletedMark()
        XCTAssertEqual(navigation.pushed.count, 1)
    }

    private func withPreferences(_ test: (ArchiveDeletedMarkPreferences, UserDefaults) throws -> Void) throws {
        let suite = "Gergram.ArchiveDeletedMarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(ArchiveDeletedMarkPreferences(defaults: defaults), defaults)
    }
}
