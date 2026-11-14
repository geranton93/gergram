import TelegramCore
import XCTest
@testable import ChatListUI

final class ContactMutualBadgeTests: XCTestCase {
    func testServerMutualContactFlagControlsBadge() {
        XCTAssertTrue(ContactMutualBadge.isVisible(flags: [.mutualContact], isSelf: false))
        XCTAssertTrue(ContactMutualBadge.isVisible(flags: [.mutualContact, .isPremium], isSelf: false))
        XCTAssertFalse(ContactMutualBadge.isVisible(flags: [.isCloseFriend, .isPremium], isSelf: false))
    }

    func testOwnAccountAndUnknownUserNeverShowBadge() {
        XCTAssertFalse(ContactMutualBadge.isVisible(flags: [.mutualContact], isSelf: true))
        XCTAssertFalse(ContactMutualBadge.isVisible(flags: nil, isSelf: false))
    }

    func testServerFlagRemovalClearsBadge() {
        var flags: UserInfoFlags = [.mutualContact, .isVerified]
        XCTAssertTrue(ContactMutualBadge.isVisible(flags: flags, isSelf: false))
        flags.remove(.mutualContact)
        XCTAssertFalse(ContactMutualBadge.isVisible(flags: flags, isSelf: false))
    }
}
