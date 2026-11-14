import InAppSettings
import XCTest
@testable import PeerInfoUI

final class PeerMediaVisibleSelectionTests: XCTestCase {
    private enum Mode: Equatable {
        case stories
        case photos
        case files
        case similarChannels
    }

    private let order: [Mode] = [.stories, .photos, .files, .similarChannels]

    func testHiddenCurrentAndInitialModesFallBackToVisibleTabs() {
        let allow: (Mode) -> Bool = { $0 != .stories }
        XCTAssertEqual(peerMediaVisibleSelection(selected: nil, initial: .stories, visible: [.photos, .files], preferredOrder: order, isAllowed: allow), .photos)
        XCTAssertEqual(peerMediaVisibleSelection(selected: .stories, initial: nil, visible: [.photos, .files], preferredOrder: order, isAllowed: allow), .files)
        XCTAssertNil(peerMediaVisibleSelection(selected: .stories, initial: .stories, visible: [], preferredOrder: order, isAllowed: allow))
    }

    func testVisibleSelectionAndExistingFallbackStayAvailable() {
        XCTAssertEqual(peerMediaVisibleSelection(selected: .photos, initial: .stories, visible: [.stories, .photos, .files], preferredOrder: order, isAllowed: { _ in true }), .photos)
        XCTAssertEqual(peerMediaVisibleSelection(selected: .similarChannels, initial: nil, visible: [.stories, .photos, .files], preferredOrder: order, isAllowed: { $0 != .similarChannels }), .files)
        XCTAssertEqual(peerMediaVisibleSelection(selected: .stories, initial: nil, visible: [], preferredOrder: order, isAllowed: { _ in true }), .stories)
    }

    func testProfileStoryPreferenceMigratesAndPersistsIndependently() throws {
        let before = try JSONDecoder().decode(AdditionalSettings.self, from: Data(#"{"ti":true,"hcls":true}"#.utf8))
        XCTAssertFalse(before.hideProfileStories)
        XCTAssertTrue(before.hideChatListStories)
        let after = before.withUpdatedHideProfileStories(true).withUpdatedHideChatListStories(false)
        XCTAssertTrue(after.hideProfileStories)
        XCTAssertFalse(after.hideChatListStories)
        XCTAssertEqual(try JSONDecoder().decode(AdditionalSettings.self, from: JSONEncoder().encode(after)), after)
    }
}
