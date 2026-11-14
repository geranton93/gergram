import XCTest
import Postbox
import TelegramCore
@testable import PeerInfoUI

final class ProfilePeerIdTextTests: XCTestCase {
    func testTelegramAPIUsesTheExistingUnsignedProfileIDs() {
        for namespace in [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel] {
            let peerId = PeerId(namespace: namespace, id: ._internalFromInt64Value(42))
            XCTAssertEqual(profilePeerIdText(peerId, format: .telegramAPI), "42")
        }
    }

    func testBotAPIKeepsUserIDsAndDistinguishesGroupAndChannelIDs() {
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1_099_511_627_775))
        let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(42))
        let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(42))
        let monoforum = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3_000_000_000_000))

        XCTAssertEqual(profilePeerIdText(user, format: .botAPI), "1099511627775")
        XCTAssertEqual(profilePeerIdText(group, format: .botAPI), "-42")
        XCTAssertEqual(profilePeerIdText(channel, format: .botAPI), "-1000000000042")
        XCTAssertEqual(profilePeerIdText(monoforum, format: .botAPI), "-4000000000000")
    }

    func testBotAPIOmitsUnsupportedNamespacesAndInvalidRanges() {
        let secretChat = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(42))
        let invalidChannel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1_000_000_000_000))

        XCTAssertNil(profilePeerIdText(secretChat, format: .botAPI))
        XCTAssertNil(profilePeerIdText(invalidChannel, format: .botAPI))
    }
}
