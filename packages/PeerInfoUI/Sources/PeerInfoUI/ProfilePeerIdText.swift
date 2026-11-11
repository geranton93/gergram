import InAppSettings
import Postbox
import TelegramCore

func profilePeerIdText(_ peerId: PeerId, format: ProfilePeerIdFormat) -> String? {
    let id = peerId.id._internalGetInt64Value()
    switch format {
    case .telegramAPI:
        return String(id)
    case .botAPI:
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser where (1...0xff_ffff_ffff).contains(id):
            return String(id)
        case Namespaces.Peer.CloudGroup where (1...999_999_999_999).contains(id):
            return String(-id)
        case Namespaces.Peer.CloudChannel where (1...997_852_516_352).contains(id) || (1_002_147_483_649...3_000_000_000_000).contains(id):
            return String(-1_000_000_000_000 - id)
        default:
            return nil
        }
    }
}
