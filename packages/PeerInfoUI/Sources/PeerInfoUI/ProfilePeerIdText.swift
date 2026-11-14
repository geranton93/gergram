import Foundation
import InAppSettings
import Postbox
import TelegramCore
import TGUIKit

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

func profilePeerIdLabel(for peer: Peer, cachedData: CachedPeerData?) -> String {
    let statistics = (cachedData as? CachedChannelData).flatMap { data in
        data.flags.contains(.canViewStats) ? Int(data.statsDatacenterId) : nil
    }
    let photoResource = peer.smallProfileImage?.resource
    let profilePhoto = (photoResource as? CloudPeerPhotoSizeMediaResource)?.datacenterId
        ?? (photoResource as? CloudPhotoSizeMediaResource)?.datacenterId

    switch ProfileDataCenter(statistics: statistics, profilePhoto: profilePhoto) {
    case let .statistics(id):
        return String(format: localizedString("Gergram.Profile.PeerIDStatisticsDataCenter"), String(id))
    case let .profilePhoto(id):
        return String(format: localizedString("Gergram.Profile.PeerIDPhotoDataCenter"), String(id))
    case nil:
        return "PEER ID"
    }
}
