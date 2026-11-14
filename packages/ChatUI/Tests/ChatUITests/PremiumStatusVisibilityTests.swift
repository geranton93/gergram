import Foundation
import InAppSettings
import Postbox
import PremiumStatusUI
import TelegramCore
import XCTest

final class PremiumStatusVisibilityTests: XCTestCase {
    private func user(flags: UserInfoFlags, status: PeerEmojiStatus? = nil, icon: Int64? = nil) -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1)),
                     accessHash: nil, firstName: "Sender", lastName: nil, username: nil, phone: nil,
                     photo: [], botInfo: nil, restrictionInfo: nil, flags: flags, emojiStatus: status,
                     usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
                     profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: icon)
    }

    func testDecorativeStatusAndPremiumBadgeReserveNoSpaceWhenHidden() {
        let status = PeerEmojiStatus(content: .emoji(fileId: 42), expirationDate: nil)
        let premium = user(flags: [.isPremium])
        for peer in [premium, user(flags: [], status: status)] {
            XCTAssertEqual(PremiumStatusControl.controlSize(peer, false, left: false)?.width, 16)
            XCTAssertNil(PremiumStatusControl.controlSize(peer, false, left: false, hidesDecorativeStatus: true))
        }
        XCTAssertTrue(premium.flags.contains(.isPremium))
    }

    func testVerifiedAndSafetyBadgesRetainTheirSpace() {
        let status = PeerEmojiStatus(content: .emoji(fileId: 42), expirationDate: nil)
        let verified = user(flags: [.isVerified, .isPremium], status: status, icon: 7)
        XCTAssertEqual(PremiumStatusControl.controlSize(verified, false, left: false)?.width, 34)
        XCTAssertEqual(PremiumStatusControl.controlSize(verified, false, left: false, hidesDecorativeStatus: true)?.width, 16)
        XCTAssertEqual(PremiumStatusControl.controlSize(verified, false, left: true, hidesDecorativeStatus: true)?.width, 16)
        for flag: UserInfoFlags in [.isScam, .isFake] {
            let peer = user(flags: [flag, .isPremium], status: status)
            XCTAssertEqual(PremiumStatusControl.controlSize(peer, false, left: false, hidesDecorativeStatus: true)?.width, 36)
        }
    }

    func testPreferenceDefaultsToVisiblePersistsAndDisposesObserver() throws {
        let suite = "Gergram.PremiumStatus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "otherPreference")

        let preferences = PremiumStatusVisibilityPreferences(defaults: defaults)
        var updates: [Bool] = []
        let subscription = preferences.signal.start(next: { updates.append($0) })
        preferences.setHidden(true)
        preferences.setHidden(true)

        let reopened = PremiumStatusVisibilityPreferences(defaults: defaults)
        XCTAssertTrue(reopened.isHidden)
        preferences.setHidden(false)
        subscription.dispose()
        preferences.setHidden(true)

        XCTAssertEqual(updates, [false, true, false])
        XCTAssertTrue(defaults.bool(forKey: "otherPreference"))
    }
}
