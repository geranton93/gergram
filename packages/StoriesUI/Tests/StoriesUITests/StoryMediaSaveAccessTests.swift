import XCTest
@testable import StoriesUI

final class StoryMediaSaveAccessTests: XCTestCase {
    func testOwnStoriesRemainSaveableWithAndWithoutPremium() {
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: true, isForwardingDisabled: true, isPremium: false, hasMediaCall: false), .save)
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: true, isForwardingDisabled: false, isPremium: true, hasMediaCall: true), .save)
    }

    func testPermittedRemoteStoriesRetainPremiumRequirement() {
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: false, isForwardingDisabled: false, isPremium: false, hasMediaCall: false), .premiumRequired)
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: false, isForwardingDisabled: false, isPremium: true, hasMediaCall: false), .save)
    }

    func testRemoteProtectionAndCallRestrictionsTakePrecedence() {
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: false, isForwardingDisabled: true, isPremium: true, hasMediaCall: false), .unavailable)
        XCTAssertEqual(StoryMediaSaveAccess(isOwn: false, isForwardingDisabled: false, isPremium: true, hasMediaCall: true), .unavailable)
    }
}
