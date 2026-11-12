import AppKit
import InAppSettings
import XCTest
@testable import ChatUI

final class ChatMessageContextMenuTests: XCTestCase {
    func testReferenceDefaults() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MessageContextMenuPreferences(defaults: defaults)

        XCTAssertEqual(preferences.visibility(for: .reactionsPanel), .shown)
        XCTAssertEqual(preferences.visibility(for: .viewsPanel), .shown)
        XCTAssertEqual(preferences.visibility(for: .hideMessage), .hidden)
        XCTAssertEqual(preferences.visibility(for: .senderSearch), .extended)
        XCTAssertEqual(preferences.visibility(for: .messageDetails), .extended)
    }

    func testSelectionsPersistIndependentlyAndUnknownValueUsesDefault() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MessageContextMenuPreferences(defaults: defaults)

        preferences.setVisibility(.shown, for: .hideMessage)
        preferences.setVisibility(.hidden, for: .senderSearch)
        defaults.set("unsupported", forKey: "gergram.chat.messageContextMenu.messageDetails")

        let reloaded = MessageContextMenuPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertTrue(reloaded.isVisible(.hideMessage, extendedMenu: false))
        XCTAssertFalse(reloaded.isVisible(.senderSearch, extendedMenu: true))
        XCTAssertFalse(reloaded.isVisible(.messageDetails, extendedMenu: false))
        XCTAssertTrue(reloaded.isVisible(.messageDetails, extendedMenu: true))
        XCTAssertEqual(reloaded.visibility(for: .viewsPanel), .shown)
    }

    func testExtendedMenuModifiersMatchMacReference() {
        XCTAssertTrue(ChatMessageContextMenuModifier.isExtended(.shift))
        XCTAssertTrue(ChatMessageContextMenuModifier.isExtended(.command))
        XCTAssertTrue(ChatMessageContextMenuModifier.isExtended([.shift, .capsLock]))
        XCTAssertFalse(ChatMessageContextMenuModifier.isExtended([]))
        XCTAssertFalse(ChatMessageContextMenuModifier.isExtended(.control))
        XCTAssertFalse(ChatMessageContextMenuModifier.isExtended(.option))
        XCTAssertFalse(ChatMessageContextMenuModifier.isExtended([.shift, .command]))
        XCTAssertFalse(ChatMessageContextMenuModifier.isExtended([.shift, .control]))
    }
}
