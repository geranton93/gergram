import Postbox
import TelegramCore
import XCTest
@testable import TelegramLinks

final class GergramPeerRouteTests: XCTestCase {
    func testExplicitDestinationsAndNamespaces() throws {
        let cases: [(String, GergramPeerRoute.Destination, PeerId.Namespace)] = [
            ("gergram://peer/user/42", .peer, Namespaces.Peer.CloudUser),
            ("gergram://chat/group/42", .chat, Namespaces.Peer.CloudGroup),
            ("GERGRAM://CHAT/channel/42", .chat, Namespaces.Peer.CloudChannel),
            ("gergram://chat/user/42", .chat, Namespaces.Peer.CloudUser)
        ]
        for (url, destination, namespace) in cases {
            let route = try XCTUnwrap(GergramPeerRoute(url: url), url)
            XCTAssertEqual(route.destination, destination, url)
            XCTAssertEqual(route.peerId.namespace, namespace, url)
            XCTAssertEqual(route.peerId.id._internalGetInt64Value(), 42, url)
        }
    }

    func testBotAPIIDsResolveToExactNamespacedValues() throws {
        let cases: [(String, PeerId.Namespace, Int64)] = [
            ("1099511627775", Namespaces.Peer.CloudUser, 1_099_511_627_775),
            ("-999999999999", Namespaces.Peer.CloudGroup, 999_999_999_999),
            ("-1000000000042", Namespaces.Peer.CloudChannel, 42),
            ("-1997852516352", Namespaces.Peer.CloudChannel, 997_852_516_352),
            ("-2002147483649", Namespaces.Peer.CloudChannel, 1_002_147_483_649),
            ("-4000000000000", Namespaces.Peer.CloudChannel, 3_000_000_000_000)
        ]
        for (value, namespace, id) in cases {
            let route = try XCTUnwrap(GergramPeerRoute(url: "gergram://chat/bot-api/" + value), value)
            XCTAssertEqual(route.peerId.namespace, namespace, value)
            XCTAssertEqual(route.peerId.id._internalGetInt64Value(), id, value)
        }
    }

    func testInvalidIDsAndUnexpectedURLComponentsAreRejected() {
        let invalid = [
            "tg://peer/user/42", "gergram://settings/user/42", "gergram://peer.example/user/42",
            "gergram://user@peer/user/42", "gergram://peer:443/user/42",
            "gergram://peer/user/42#profile", "gergram://peer/user/42?account=9",
            "gergram://peer/user/42/", "gergram://peer/user/%34%32", "gergram://peer/user/+42",
            "gergram://peer/user/042", "gergram://peer/user/４２", "gergram://peer/user/0",
            "gergram://peer/user/-42", "gergram://peer/user/1099511627776",
            "gergram://peer/group/1000000000000", "gergram://chat/channel/997852516353",
            "gergram://chat/bot-api/-1000000000000", "gergram://chat/bot-api/-2000000000000",
            "gergram://chat/bot-api/-4000000000001", "gergram://chat/bot-api/-9223372036854775808"
        ]
        for url in invalid {
            XCTAssertNil(GergramPeerRoute(url: url), url)
        }
    }
}
