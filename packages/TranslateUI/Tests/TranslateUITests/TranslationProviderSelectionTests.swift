import XCTest
@testable import TranslateUI

final class TranslationProviderSelectionTests: XCTestCase {
    func testGoogleRequiresEligibilityAndExplicitConsent() {
        var selection = TranslationProviderSelection()
        XCTAssertEqual(selection.provider, .telegram)
        XCTAssertFalse(selection.select(.google, confirmedGoogleConsent: true))

        selection.setGoogleAvailability(true)
        XCTAssertFalse(selection.select(.google))
        XCTAssertEqual(selection.provider, .telegram)
        XCTAssertTrue(selection.select(.google, confirmedGoogleConsent: true))
        XCTAssertEqual(selection.provider, .google)
    }

    func testReturningToTelegramDoesNotReuseGoogleConsent() {
        var selection = TranslationProviderSelection()
        selection.setGoogleAvailability(true)
        selection.select(.google, confirmedGoogleConsent: true)
        XCTAssertTrue(selection.select(.telegram))
        XCTAssertFalse(selection.select(.google))
        XCTAssertEqual(selection.provider, .telegram)
    }

    func testEligibilityLossRevokesGoogleSelection() {
        var selection = TranslationProviderSelection()
        selection.setGoogleAvailability(true)
        selection.select(.google, confirmedGoogleConsent: true)
        selection.setGoogleAvailability(false)

        XCTAssertFalse(selection.isGoogleAvailable)
        XCTAssertEqual(selection.provider, .telegram)
        XCTAssertFalse(selection.select(.google, confirmedGoogleConsent: true))
    }
}
