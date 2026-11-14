import Postbox

struct LocalShadowBanRules: Codable, Equatable {
    private(set) var senderIds: Set<PeerId> = []

    mutating func setHidden(_ hidden: Bool, senderId: PeerId) {
        if hidden {
            senderIds.insert(senderId)
        } else {
            senderIds.remove(senderId)
        }
    }
}
