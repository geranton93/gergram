import Foundation
import Postbox
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatNetworkSpeedNoticeTests: XCTestCase {
    private func message(_ value: Int32) -> MessageId {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
        return MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: value)
    }

    func testDownloadRequiresTheOriginatingMessageAndUploadNeedsNoMessage() {
        let downloading = message(1)
        let unrelated = message(2)
        XCTAssertFalse(ChatNetworkSpeedNotice.isEligible(.download(.message(downloading))) { $0 == unrelated })
        XCTAssertTrue(ChatNetworkSpeedNotice.isEligible(.download(.message(downloading))) { $0 == downloading })
        XCTAssertTrue(ChatNetworkSpeedNotice.isEligible(.upload) { _ in
            XCTFail("The native upload event has no message ID")
            return false
        })
    }

    func testConfiguredCooldownDeduplicatesQueuedEventsAcrossControllers() {
        let notice = ChatNetworkSpeedNotice()
        let network = NSObject()
        let period = 120.0
        XCTAssertTrue(notice.claim(network: network, configuredPeriod: period, now: 100))
        XCTAssertFalse(notice.claim(network: network, configuredPeriod: period, now: 100))
        XCTAssertFalse(notice.claim(network: network, configuredPeriod: period, now: 220))
        XCTAssertTrue(notice.claim(network: network, configuredPeriod: period, now: 221))
        XCTAssertFalse(notice.claim(network: network, configuredPeriod: period, now: 222))
    }

    func testCooldownUsesCurrentConfigurationAndValidatesBadPeriods() {
        let notice = ChatNetworkSpeedNotice()
        let network = NSObject()
        XCTAssertTrue(notice.claim(network: network, configuredPeriod: 200, now: 100))
        XCTAssertFalse(notice.claim(network: network, configuredPeriod: 200, now: 150))
        XCTAssertTrue(notice.claim(network: network, configuredPeriod: 40, now: 150))

        for invalid in [-1, .infinity, .nan] as [TimeInterval] {
            let network = NSObject()
            XCTAssertTrue(notice.claim(network: network, configuredPeriod: invalid, now: 100))
            XCTAssertFalse(notice.claim(network: network, configuredPeriod: invalid, now: 3_700))
            XCTAssertTrue(notice.claim(network: network, configuredPeriod: invalid, now: 3_701))
        }
    }

    func testCooldownSeparatesNetworkIdentityAndDoesNotRetainNetworks() {
        final class Reference {
            weak var network: NSObject?
        }

        let notice = ChatNetworkSpeedNotice()
        let reference = Reference()
        do {
            let first = NSObject()
            reference.network = first
            let second = NSObject()
            XCTAssertTrue(notice.claim(network: first, configuredPeriod: 200, now: 100))
            XCTAssertTrue(notice.claim(network: second, configuredPeriod: 200, now: 100))
        }
        XCTAssertNil(reference.network)
        XCTAssertTrue(notice.claim(network: NSObject(), configuredPeriod: 200, now: 100))
    }

    func testSpeedFactorRemainsSafeForLocalizedIntegerFormatting() {
        XCTAssertEqual(ChatNetworkSpeedNotice.speedFactor(4), 4)
        for invalid in [-1, 0, .infinity, .nan, Double(Int32.max) + 1] as [Double] {
            XCTAssertEqual(ChatNetworkSpeedNotice.speedFactor(invalid), 10)
        }
    }
}
