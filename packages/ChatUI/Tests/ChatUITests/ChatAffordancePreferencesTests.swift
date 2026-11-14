@testable import ChatUI
import Foundation
import InAppSettings
import SwiftSignalKit
import XCTest

final class ChatAffordancePreferencesTests: XCTestCase {
    func testPreferencesDefaultToVisibleAndPersistIndependently() throws {
        let suite = "Gergram.ChatAffordance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = ChatAffordancePreferences(defaults: defaults)
        var fastShare: [Bool] = []
        var greeting: [Bool] = []
        let shareObserver = preferences.hidesFastShareSignal.start(next: { fastShare.append($0) })
        let greetingObserver = preferences.hidesGreetingStickerSignal.start(next: { greeting.append($0) })
        preferences.setHidesFastShare(true)
        preferences.setHidesFastShare(true)
        XCTAssertTrue(ChatAffordancePreferences(defaults: defaults).hidesFastShare)
        XCTAssertFalse(ChatAffordancePreferences(defaults: defaults).hidesGreetingSticker)
        preferences.setHidesGreetingSticker(true)
        XCTAssertTrue(ChatAffordancePreferences(defaults: defaults).hidesGreetingSticker)
        preferences.setHidesFastShare(false)
        shareObserver.dispose()
        greetingObserver.dispose()
        preferences.setHidesFastShare(true)
        preferences.setHidesGreetingSticker(false)

        XCTAssertEqual(fastShare, [false, true, false])
        XCTAssertEqual(greeting, [false, true])
    }

    func testHiddenGreetingDoesNotStartLoading() {
        var loads = 0
        var result: [(Bool, String?)] = []
        let subscription = ChatGreetingSticker.suggestions(hidden: .single(true), load: {
            loads += 1
            return .single("suggested sticker")
        }).start(next: { result.append($0) })
        defer { subscription.dispose() }

        XCTAssertEqual(loads, 0)
        XCTAssertEqual(result.map(\.0), [true])
        XCTAssertEqual(result.map(\.1), [nil])
    }

    func testChangingGreetingVisibilityCancelsLoadAndClearsStaleSuggestion() {
        let hidden = ValuePromise(false, ignoreRepeated: true)
        var loads = 0
        var cancellations = 0
        var emit: ((String?) -> Void)?
        var result: [(Bool, String?)] = []
        let subscription = ChatGreetingSticker.suggestions(hidden: hidden.get(), load: {
            loads += 1
            return Signal { subscriber in
                emit = { subscriber.putNext($0) }
                return ActionDisposable {
                    cancellations += 1
                }
            }
        }).start(next: { result.append($0) })

        XCTAssertEqual(loads, 1)
        emit?("first")
        let stale = emit
        hidden.set(true)
        stale?("stale")
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(result.map(\.0), [false, false, true])
        XCTAssertEqual(result.map(\.1), [nil, "first", nil])

        hidden.set(false)
        XCTAssertEqual(loads, 2)
        emit?("second")
        subscription.dispose()
        XCTAssertEqual(cancellations, 2)
        XCTAssertEqual(result.map(\.1), [nil, "first", nil, nil, "second"])
    }
}
