import XCTest
@testable import TelegramLinks

final class GergramSettingsRouteTests: XCTestCase {
    func testAllowlistedScreens() {
        XCTAssertEqual(GergramSettingsRoute(url: "gergram://settings/general/message-context-menu"), .messageContextMenu)
        XCTAssertEqual(GergramSettingsRoute(url: "gergram://settings/general/on-device-transcription-language"), .transcriptionLanguage)
        XCTAssertEqual(GergramSettingsRoute(url: "gergram://settings/appearance/message-bubble-corners"), .messageBubbleCorners)
        XCTAssertEqual(GergramSettingsRoute(url: "GERGRAM://SETTINGS/privacy/locally-hidden-senders"), .locallyHiddenSenders)
        XCTAssertEqual(GergramSettingsRoute(url: "gergram://settings/privacy/message-filters"), .messageFilters)
        XCTAssertEqual(GergramSettingsRoute(url: "GERGRAM://SETTINGS/privacy/local-message-archive"), .localMessageArchive)
    }

    func testOnlyTheForkSchemeIsRecognized() {
        XCTAssertTrue(GergramSettingsRoute.recognizesScheme("GERGRAM:invalid"))
        XCTAssertFalse(GergramSettingsRoute.recognizesScheme("tg://settings/general/message-context-menu"))
        XCTAssertFalse(GergramSettingsRoute.recognizesScheme("https://example.test/gergram://settings/general/message-context-menu"))
    }

    func testRejectsOtherAuthoritiesAndNoncanonicalPaths() {
        let urls = [
            "tg://settings/general/message-context-menu",
            "gergram:settings/general/message-context-menu",
            "gergram:///settings/general/message-context-menu",
            "gergram://settings.example.test/general/message-context-menu",
            "gergram://user@settings/general/message-context-menu",
            "gergram://settings:443/general/message-context-menu",
            "gergram://settings:/general/message-context-menu",
            "gergram://%73ettings/general/message-context-menu",
            "gergram://settings/general/%6dessage-context-menu",
            "gergram://settings/General/message-context-menu",
            "gergram://settings/general//message-context-menu",
            "gergram://settings/general/../privacy/locally-hidden-senders",
            "gergram://settings/general/message-context-menu/",
            "gergram://settings/privacy/locally-hidden-senders/remove",
            "gergram://settings/privacy/locally-hidden-senders?account=123",
            "gergram://settings/privacy/locally-hidden-senders?",
            "gergram://settings/privacy/locally-hidden-senders#reset",
            "gergram://settings/privacy/message-filters?account=123",
            "gergram://settings/privacy/message-filters?import=https://example.test/rules",
            "gergram://settings/privacy/local-message-archive#clear",
            "gergram://settings/privacy/local-message-archive/clear",
            "gergram://settings/privacy/local-message-%61rchive",
            "gergram://settings/privacy/reset",
            "gergram://settings/general/on-device-transcription-language?locale=en_US",
            "gergram://settings/appearance/message-bubble-corners#0",
            "gergram://settings/appearance/message-bubble-corners/reset",
            "gergram://settings/devices/terminate-sessions"
        ]
        for url in urls {
            XCTAssertNil(GergramSettingsRoute(url: url), url)
        }
    }
}
