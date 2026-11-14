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

    func testDownloadEventRequiresExactResourceProvenance() {
        let downloading = message(1)
        let resourceId = LocalFileMediaResource(fileId: 1).id
        XCTAssertNil(ChatNetworkSpeedNotice.Download(event: .download(.message(downloading)), resourceId: nil))
        XCTAssertNil(ChatNetworkSpeedNotice.Download(event: .upload, resourceId: resourceId))
        let download = ChatNetworkSpeedNotice.Download(event: .download(.message(downloading)), resourceId: resourceId)
        XCTAssertEqual(download?.messageId, downloading)
        XCTAssertEqual(download?.resourceId, resourceId)
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

    func testPendingDownloadsAreAccountScopedDeduplicatedAndClearedByPresentation() {
        let notice = ChatNetworkSpeedNotice()
        let first = NSObject()
        let second = NSObject()
        let download = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: LocalFileMediaResource(fileId: 1).id)
        notice.enqueue(download, network: first, now: 10)
        notice.enqueue(download, network: first, now: 11)
        notice.enqueue(download, network: second, now: 11)
        XCTAssertEqual(notice.pendingDownloads(network: first, now: 12), [download])
        XCTAssertTrue(notice.claim(network: first, configuredPeriod: 10, now: 12))
        notice.enqueue(download, network: first, configuredPeriod: 10, now: 13)
        XCTAssertEqual(notice.pendingDownloads(network: first, now: 13), [])
        XCTAssertEqual(notice.pendingDownloads(network: second, now: 13), [download])
        notice.discardPendingDownloads(network: second)
        XCTAssertEqual(notice.pendingDownloads(network: second, now: 14), [])
    }

    func testPendingDownloadsExpireFromFirstEventAndStayBounded() {
        let notice = ChatNetworkSpeedNotice()
        let network = NSObject()
        let download = ChatNetworkSpeedNotice.Download(messageId: message(1), resourceId: LocalFileMediaResource(fileId: 1).id)
        notice.enqueue(download, network: network, now: 1)
        notice.enqueue(download, network: network, now: 300)
        XCTAssertEqual(notice.pendingDownloads(network: network, now: 301), [])
        for id in 1 ... 17 {
            notice.enqueue(.init(messageId: message(Int32(id)), resourceId: LocalFileMediaResource(fileId: Int64(id)).id), network: network, now: 4_000)
        }
        XCTAssertEqual(notice.pendingDownloads(network: network, now: 4_001).map(\.messageId), (2 ... 17).map { message(Int32($0)) })
    }

    func testSpeedFactorRemainsSafeForLocalizedIntegerFormatting() {
        XCTAssertEqual(ChatNetworkSpeedNotice.speedFactor(4), 4)
        for invalid in [-1, 0, .infinity, .nan, Double(Int32.max) + 1] as [Double] {
            XCTAssertEqual(ChatNetworkSpeedNotice.speedFactor(invalid), 10)
        }
    }
}
