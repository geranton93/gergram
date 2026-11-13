import Foundation
import InAppSettings
import XCTest

final class ChatListStoryPreferenceTests: XCTestCase {
    func testLegacyPreferencesKeepStoriesVisible() throws {
        let data = Data(#"{"ti":true,"pc":true,"dgps":true}"#.utf8)
        let preferences = try JSONDecoder().decode(AdditionalSettings.self, from: data)
        XCTAssertFalse(preferences.hideChatListStories)
        XCTAssertTrue(preferences.useTouchId)
        XCTAssertTrue(preferences.previewChats)
        XCTAssertTrue(preferences.disableGlobalPeerSearch)
    }

    func testVisibilityRoundTripsAndCanBeRestored() throws {
        let visible = AdditionalSettings.defaultSettings
        let hidden = visible.withUpdatedHideChatListStories(true)
        XCTAssertNotEqual(hidden, visible)
        let data = try JSONEncoder().encode(hidden)
        let decoded = try JSONDecoder().decode(AdditionalSettings.self, from: data)
        XCTAssertEqual(decoded, hidden)
        XCTAssertEqual(decoded.withUpdatedHideChatListStories(false), visible)
    }

    func testChangingOtherPreferencesPreservesStoryVisibility() {
        let hidden = AdditionalSettings.defaultSettings.withUpdatedHideChatListStories(true)
        let updated = hidden.withUpdatedTouchId(true)
            .withUpdatedPreviewChats(true)
            .withUpdatedDisableGlobalPeerSearch(true)
        XCTAssertTrue(updated.hideChatListStories)
        XCTAssertTrue(updated.useTouchId)
        XCTAssertTrue(updated.previewChats)
        XCTAssertTrue(updated.disableGlobalPeerSearch)
    }
}
