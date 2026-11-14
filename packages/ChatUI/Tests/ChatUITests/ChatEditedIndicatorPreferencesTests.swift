import Foundation
import InAppSettings
import XCTest

final class ChatEditedIndicatorPreferencesTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "Gergram.ChatEditedIndicatorPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }

    func testAbsentAndUnknownPreferencesUseText() throws {
        try withDefaults { defaults in
            func initialStyle() -> ChatEditedIndicatorStyle? {
                var result: ChatEditedIndicatorStyle?
                let disposable = ChatEditedIndicatorPreferences(defaults: defaults).signal.start(next: { result = $0 })
                disposable.dispose()
                return result
            }

            XCTAssertEqual(initialStyle(), .text)
            defaults.set("unrecognized-future-style", forKey: "Gergram.Chat.EditedIndicatorStyle")
            XCTAssertEqual(initialStyle(), .text)
        }
    }

    func testChangesArePersistedAndBroadcastOnce() throws {
        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            var emissions: [ChatEditedIndicatorStyle] = []
            let disposable = preferences.signal.start(next: { emissions.append($0) })

            preferences.set(.icon)
            preferences.set(.icon)
            preferences.set(.hidden)
            XCTAssertEqual(emissions, [.text, .icon, .hidden])

            var reloaded: ChatEditedIndicatorStyle?
            let reload = ChatEditedIndicatorPreferences(defaults: defaults).signal.start(next: { reloaded = $0 })
            reload.dispose()
            XCTAssertEqual(reloaded, .hidden)

            disposable.dispose()
            preferences.set(.text)
            XCTAssertEqual(emissions, [.text, .icon, .hidden])
        }
    }

    func testDisposingSignalReleasesSubscriber() throws {
        final class Subscriber {
            func receive(_ style: ChatEditedIndicatorStyle) {}
        }

        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            weak var weakSubscriber: Subscriber?
            let disposable = autoreleasepool {
                let subscriber = Subscriber()
                weakSubscriber = subscriber
                return preferences.signal.start(next: subscriber.receive)
            }

            XCTAssertNotNil(weakSubscriber)
            disposable.dispose()
            XCTAssertNil(weakSubscriber)
        }
    }

    func testCustomLabelAndStylePersistAndPublishTogether() throws {
        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            var labels: [String?] = []
            var styles: [ChatEditedIndicatorStyle] = []
            let disposable = preferences.appearanceSignal.start(next: {
                labels.append($0.customText)
                styles.append($0.style)
            })
            defer { disposable.dispose() }

            XCTAssertTrue(preferences.setCustomText("  revised  "))
            XCTAssertTrue(preferences.setCustomText("revised"))
            preferences.set(.icon)
            preferences.set(.text)
            XCTAssertEqual(labels, [nil, "revised", "revised", "revised"])
            XCTAssertEqual(styles, [.text, .text, .icon, .text])
            XCTAssertEqual(ChatEditedIndicatorPreferences(defaults: defaults).appearance.customText, "revised")
        }
    }

    func testCustomLabelRejectsMultilineBidiAndOversizedText() throws {
        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            XCTAssertTrue(preferences.setCustomText("👩🏽‍💻 revised"))
            for value in ["line\nbreak", "left\u{202e}right", "\u{200d}\u{200c}", "\u{fe0f}",
                          String(repeating: "x", count: 17),
                          String(repeating: "👩🏽‍💻", count: 7)] {
                XCTAssertFalse(preferences.setCustomText(value))
                XCTAssertEqual(preferences.appearance.customText, "👩🏽‍💻 revised")
            }
            XCTAssertTrue(preferences.setCustomText("  "))
            XCTAssertNil(ChatEditedIndicatorPreferences(defaults: defaults).appearance.customText)
        }
    }

    func testCustomLabelAllowsEmojiWithinBothLimits() throws {
        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            let label = String(repeating: "👩🏽‍💻", count: 6)
            XCTAssertGreaterThan(label.utf16.count, ChatEditedIndicatorPreferences.maximumCustomTextLength)
            XCTAssertLessThanOrEqual(label.utf16.count, ChatEditedIndicatorPreferences.maximumCustomTextUTF16Length)
            XCTAssertTrue(preferences.setCustomText(label))
            XCTAssertEqual(preferences.appearance.customText, label)
        }
    }

    func testResetPublishesOneDefaultAndClearsCustomLabel() throws {
        try withDefaults { defaults in
            let preferences = ChatEditedIndicatorPreferences(defaults: defaults)
            preferences.set(.icon)
            XCTAssertTrue(preferences.setCustomText("revised"))
            var updates: [ChatEditedIndicatorAppearance] = []
            let disposable = preferences.appearanceSignal.start(next: { updates.append($0) })
            defer { disposable.dispose() }
            preferences.reset()
            XCTAssertEqual(updates.map(\.style), [.icon, .text])
            XCTAssertEqual(updates.map(\.customText), ["revised", nil])
            let reloaded = ChatEditedIndicatorPreferences(defaults: defaults).appearance
            XCTAssertEqual(reloaded.style, .text)
            XCTAssertNil(reloaded.customText)
        }
    }
}
