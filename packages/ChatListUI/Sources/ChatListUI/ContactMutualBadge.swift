import TelegramCore

enum ContactMutualBadge {
    static func isVisible(flags: UserInfoFlags?, isSelf: Bool) -> Bool {
        return !isSelf && flags?.contains(.mutualContact) == true
    }
}
