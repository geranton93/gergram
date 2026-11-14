import Foundation
import Postbox
import TelegramCore
import XCTest
@testable import InAppSettings

final class LocalShadowBanRulesTests: XCTestCase {
    func testRulesRoundTripAndRestoreOnlyTheSelectedNamespace() throws {
        let rawId = PeerId.Id._internalFromInt64Value(1 << 42)
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: rawId)
        let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: rawId)
        var rules = LocalShadowBanRules()
        XCTAssertTrue(rules.senderIds.isEmpty)

        rules.setHidden(true, senderId: user)
        rules.setHidden(true, senderId: channel)
        rules.setHidden(true, senderId: user)
        let encoded = try JSONEncoder().encode(rules)
        var reloaded = try JSONDecoder().decode(LocalShadowBanRules.self, from: encoded)
        XCTAssertEqual(reloaded.senderIds, [user, channel])

        reloaded.setHidden(false, senderId: user)
        reloaded.setHidden(false, senderId: user)
        XCTAssertEqual(reloaded.senderIds, [channel])
        XCTAssertEqual(rules.senderIds, [user, channel])
        XCTAssertTrue(LocalShadowBanRules().senderIds.isEmpty)
    }
}
