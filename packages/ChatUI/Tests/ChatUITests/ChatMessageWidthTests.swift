import Foundation
import InAppSettings
import XCTest

final class ChatMessageWidthTests: XCTestCase {
    func testWidthPresetsKeepTheNativeDefaultAndBoundAlternatives() {
        XCTAssertEqual(ChatMessageWidth.compact.maximumBubbleWidth, 360)
        XCTAssertEqual(ChatMessageWidth.standard.maximumBubbleWidth, 450)
        XCTAssertEqual(ChatMessageWidth.wide.maximumBubbleWidth, 600)
    }

    func testMissingAndUnknownSettingsUseStandard() throws {
        let suite = "Gergram.ChatMessageWidth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ChatMessageWidthPreferences(defaults: defaults).width, .standard)
        defaults.set("unknown", forKey: "Gergram.Chat.MessageWidth")
        XCTAssertEqual(ChatMessageWidthPreferences(defaults: defaults).width, .standard)
    }

    func testWidthChangesPersistAndStopAfterDisposal() throws {
        let suite = "Gergram.ChatMessageWidth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = ChatMessageWidthPreferences(defaults: defaults)
        var widths: [ChatMessageWidth] = []
        let subscription = preferences.signal.start(next: { widths.append($0) })
        preferences.set(.compact)
        preferences.set(.compact)
        preferences.set(.wide)
        subscription.dispose()
        preferences.set(.standard)

        XCTAssertEqual(widths, [.standard, .compact, .wide])
        XCTAssertEqual(ChatMessageWidthPreferences(defaults: defaults).width, .standard)
    }
}
