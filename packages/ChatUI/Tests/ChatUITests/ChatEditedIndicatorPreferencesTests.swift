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
}
