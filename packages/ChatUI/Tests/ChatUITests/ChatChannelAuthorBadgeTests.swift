import TelegramCore
import XCTest
@testable import ChatUI

final class ChatChannelAuthorBadgeTests: XCTestCase {
    private let group: TelegramChannelInfo = .group(.init(flags: []))
    private let broadcast: TelegramChannelInfo = .broadcast(.init(flags: []))

    func testIncomingChannelAuthorInSupergroupShowsBadge() {
        XCTAssertTrue(ChatChannelAuthorBadge.showsDirectAuthor(in: group, author: broadcast, displaysAuthor: true, isIncoming: true))
    }

    func testOutgoingOrDifferentDisplayedAuthorDoesNotShowBadge() {
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: group, author: broadcast, displaysAuthor: true, isIncoming: false))
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: group, author: broadcast, displaysAuthor: false, isIncoming: true))
    }

    func testAnonymousGroupAuthorAndNonChannelAuthorsDoNotShowBadge() {
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: group, author: group, displaysAuthor: true, isIncoming: true))
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: group, author: nil, displaysAuthor: true, isIncoming: true))
    }

    func testBroadcastAndNonSupergroupDestinationsDoNotShowBadge() {
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: broadcast, author: broadcast, displaysAuthor: true, isIncoming: true))
        XCTAssertFalse(ChatChannelAuthorBadge.showsDirectAuthor(in: nil, author: broadcast, displaysAuthor: true, isIncoming: true))
    }
}
