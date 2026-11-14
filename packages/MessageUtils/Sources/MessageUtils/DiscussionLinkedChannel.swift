import Postbox
import TelegramCore
import TelegramTheme

public func discussionLinkedChannelId(in view: PeerView, contentSettings: ContentSettings?) -> PeerId? {
    guard let group = view.peers[view.peerId] as? TelegramChannel, group.isSupergroup,
          !group.isMonoForum, group.participationStatus != .kicked,
          group.restrictionText(contentSettings) == nil,
          let cachedData = view.cachedData as? CachedChannelData, !cachedData.isNotAccessible,
          let linkedId = cachedData.linkedDiscussionPeerId.peerId, linkedId != group.id,
          let channel = view.peers[linkedId] as? TelegramChannel, channel.isChannel,
          channel.participationStatus != .kicked,
          channel.restrictionText(contentSettings) == nil else {
        return nil
    }
    return linkedId
}
