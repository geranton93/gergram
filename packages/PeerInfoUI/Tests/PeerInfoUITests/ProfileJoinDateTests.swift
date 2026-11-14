import Foundation
import InAppSettings
import XCTest
@testable import PeerInfoUI

final class ProfileJoinDateTests: XCTestCase {
    func testUsesOnlyFullMemberPeerDate() {
        XCTAssertEqual(ProfileJoinDate.membershipTimestamp(1_700_000_000, isMember: true, isCreator: false, isFullPeer: true), 1_700_000_000)
        XCTAssertNil(ProfileJoinDate.membershipTimestamp(1_700_000_000, isMember: false, isCreator: false, isFullPeer: true))
        XCTAssertNil(ProfileJoinDate.membershipTimestamp(1_700_000_000, isMember: true, isCreator: true, isFullPeer: true))
        XCTAssertNil(ProfileJoinDate.membershipTimestamp(1_700_000_000, isMember: true, isCreator: false, isFullPeer: false))
    }

    func testOmitsUnknownAndInvalidDates() {
        for timestamp: Int32 in [0, -1] {
            XCTAssertNil(ProfileJoinDate.membershipTimestamp(timestamp, isMember: true, isCreator: false, isFullPeer: true))
        }
    }

    func testFormatsUsingSuppliedLocaleAndTimeZone() {
        let locale = Locale(identifier: "en_US")
        let utc = TimeZone(secondsFromGMT: 0)!
        let timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        let timestamp: Int32 = 1_700_006_400
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        XCTAssertEqual(ProfileJoinDate.label(for: timestamp, locale: locale, timeZone: timeZone),
                       formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp))))
        XCTAssertNotEqual(ProfileJoinDate.label(for: timestamp, locale: locale, timeZone: timeZone),
                          ProfileJoinDate.label(for: timestamp, locale: locale, timeZone: utc))
    }

    func testPreferenceDefaultsOffAndSurvivesRecreation() {
        let suite = "ProfileJoinDateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = ProfileJoinDatePreferences(defaults: defaults)
        var values: [Bool] = []
        let disposable = settings.signal.start(next: { values.append($0) })
        defer { disposable.dispose() }
        settings.setVisible(true)
        settings.setVisible(true)
        XCTAssertEqual(values, [false, true])

        let reloaded = ProfileJoinDatePreferences(defaults: defaults)
        let subscription = reloaded.signal.start(next: { XCTAssertTrue($0) })
        subscription.dispose()
        settings.setVisible(false)
        XCTAssertEqual(values, [false, true, false])
    }
}
