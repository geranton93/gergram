import Postbox
import TelegramCore

public struct GergramPeerRoute: Equatable {
    public enum Destination: String {
        case peer
        case chat
    }

    public let destination: Destination
    public let peerId: PeerId

    public init?(url: String) {
        let prefix = "gergram://"
        guard url.prefix(prefix.count).lowercased() == prefix else { return nil }
        let components = url.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              let destination = Destination(rawValue: components[0].lowercased()),
              let value = Self.decimalID(components[2]) else { return nil }

        let namespace: PeerId.Namespace
        let id: Int64
        switch components[1] {
        case "user" where Self.userIDs.contains(value):
            (namespace, id) = (Namespaces.Peer.CloudUser, value)
        case "group" where Self.groupIDs.contains(value):
            (namespace, id) = (Namespaces.Peer.CloudGroup, value)
        case "channel" where Self.isChannelID(value):
            (namespace, id) = (Namespaces.Peer.CloudChannel, value)
        case "bot-api":
            if Self.userIDs.contains(value) {
                (namespace, id) = (Namespaces.Peer.CloudUser, value)
            } else if (-999_999_999_999 ... -1).contains(value) {
                (namespace, id) = (Namespaces.Peer.CloudGroup, -value)
            } else if (-4_000_000_000_000 ... -1_000_000_000_001).contains(value),
                      Self.isChannelID(-value - 1_000_000_000_000) {
                (namespace, id) = (Namespaces.Peer.CloudChannel, -value - 1_000_000_000_000)
            } else {
                return nil
            }
        default:
            return nil
        }
        self.destination = destination
        self.peerId = PeerId(namespace: namespace, id: ._internalFromInt64Value(id))
    }

    private static let userIDs: ClosedRange<Int64> = 1...0xff_ffff_ffff
    private static let groupIDs: ClosedRange<Int64> = 1...999_999_999_999

    private static func isChannelID(_ value: Int64) -> Bool {
        return (1...997_852_516_352).contains(value) || (1_002_147_483_649...3_000_000_000_000).contains(value)
    }

    private static func decimalID(_ value: Substring) -> Int64? {
        guard value.utf8.count <= 14, let number = Int64(value), String(number) == value else { return nil }
        return number
    }
}
