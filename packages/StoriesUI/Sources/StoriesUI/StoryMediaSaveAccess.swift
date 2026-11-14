enum StoryMediaSaveAccess: Equatable {
    case save
    case premiumRequired
    case unavailable

    init(isOwn: Bool, isForwardingDisabled: Bool, isPremium: Bool, hasMediaCall: Bool) {
        if isOwn {
            self = .save
        } else if isForwardingDisabled || hasMediaCall {
            self = .unavailable
        } else {
            self = isPremium ? .save : .premiumRequired
        }
    }
}
