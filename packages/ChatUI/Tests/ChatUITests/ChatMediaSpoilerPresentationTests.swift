import Foundation
import InAppSettings
import SwiftSignalKit
import XCTest
@testable import ChatUI

final class ChatMediaSpoilerPresentationTests: XCTestCase {
    func testOnlyEligibleUnrevealedSpoilersArePreviewed() {
        for enabled in [false, true] {
            for eligible in [false, true] {
                XCTAssertEqual(
                    presentation(enabled: enabled, eligible: eligible),
                    enabled && eligible ? .previewOnly : .covered
                )
                XCTAssertEqual(presentation(enabled: enabled, eligible: eligible, forced: true), .covered)
                XCTAssertEqual(presentation(enabled: enabled, eligible: eligible, spoiler: false), .visible)
            }
        }
    }

    func testNativeExplicitRevealSurvivesToggleAndSiblingStaysCovered() {
        let explicitReveals = [false, true, false]
        XCTAssertEqual(explicitReveals.map { presentation(enabled: true, explicitlyRevealed: $0) },
            [.previewOnly, .visible, .previewOnly])
        XCTAssertEqual(explicitReveals.reversed().map { presentation(enabled: false, explicitlyRevealed: $0) },
            [.covered, .visible, .covered])
    }

    func testSurfaceWithoutNativeRevealParametersKeepsNativePresentation() {
        XCTAssertEqual(presentation(enabled: true, explicitlyRevealed: nil), .visible)
        XCTAssertEqual(presentation(enabled: false, explicitlyRevealed: nil), .visible)
    }

    func testPreferencesDefaultOffPersistAndNotifyOncePerChange() {
        let name = "gergram-spoiler-preference-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ChatMediaSpoilerPreferences(defaults: defaults)
        var observed: [Bool] = []
        let disposable = preferences.signal.start(next: { observed.append($0) })
        defer { disposable.dispose() }

        XCTAssertFalse(preferences.isEnabled)
        preferences.setEnabled(true)
        preferences.setEnabled(true)
        XCTAssertTrue(ChatMediaSpoilerPreferences(defaults: defaults).isEnabled)
        preferences.setEnabled(false)
        XCTAssertFalse(ChatMediaSpoilerPreferences(defaults: defaults).isEnabled)
        XCTAssertEqual(observed, [false, true, false])
    }

    private func presentation(
        enabled: Bool, eligible: Bool = true, forced: Bool = false, spoiler: Bool = true,
        explicitlyRevealed: Bool? = false
    ) -> ChatMediaSpoilerPresentation {
        ChatMediaSpoilerPresentation(hasSpoiler: spoiler, requiresCover: forced,
            isExplicitlyRevealed: explicitlyRevealed, revealsOrdinarySpoilers: enabled,
            isEligibleForPreview: eligible)
    }
}
