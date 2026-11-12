import XCTest
@testable import ChatUI

final class ChatBotForumControlsTests: XCTestCase {
    func testStartMatchesIOSHistoryAndThreadRules() {
        XCTAssertFalse(ChatBotForumControls.showsStart(isBot: true, isScheduled: false, historyCount: nil, threadId: nil, isBlocked: false))
        XCTAssertTrue(ChatBotForumControls.showsStart(isBot: true, isScheduled: false, historyCount: 0, threadId: nil, isBlocked: false))
        XCTAssertFalse(ChatBotForumControls.showsStart(isBot: true, isScheduled: false, historyCount: 1, threadId: nil, isBlocked: false))
        XCTAssertFalse(ChatBotForumControls.showsStart(isBot: true, isScheduled: false, historyCount: 0, threadId: 1, isBlocked: false))
        XCTAssertTrue(ChatBotForumControls.showsStart(isBot: true, isScheduled: false, historyCount: 1, threadId: 1, isBlocked: true))
        XCTAssertFalse(ChatBotForumControls.showsStart(isBot: true, isScheduled: true, historyCount: 0, threadId: nil, isBlocked: true))
        XCTAssertFalse(ChatBotForumControls.showsStart(isBot: false, isScheduled: false, historyCount: 0, threadId: nil, isBlocked: false))
    }

    func testBotStartPayloadPreviewUsesOnlyTheFirstTwentyCodeUnits() {
        XCTAssertNil(ChatBotForumControls.startPayloadPreview(""))
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview("token_1"), "token_1")
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview("01234567890123456789extra"), "01234567890123456789")
    }

    func testBotStartPayloadPreviewKeepsUnicodeCharactersWhole() {
        let prefix = String(repeating: "a", count: 19)
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview(prefix + "🇺🇦"), prefix)
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview(prefix + "e\u{301}"), prefix)
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview("👩🏾‍💻"), "👩🏾‍💻")
        XCTAssertEqual(ChatBotForumControls.startPayloadPreview("e" + String(repeating: "\u{301}", count: 25)), "…")
    }

    func testForumNavbarMatchesIOSHistoryAndThreadRules() {
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: false, isPinned: false, historyCount: nil, threadId: nil), .hidden)
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: false, isPinned: false, historyCount: 0, threadId: nil), .hidden)
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: false, isPinned: false, historyCount: 1, threadId: nil), .search)
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: false, isPinned: false, historyCount: 0, threadId: 1), .more)
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: true, isPinned: false, historyCount: 1, threadId: 1), .hidden)
        XCTAssertEqual(ChatBotForumControls.navigationAction(hasForum: true, isPreview: false, isPinned: true, historyCount: 1, threadId: 1), .hidden)
        XCTAssertNil(ChatBotForumControls.navigationAction(hasForum: false, isPreview: false, isPinned: false, historyCount: 1, threadId: nil))
    }
}
