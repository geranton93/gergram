import TelegramCore

enum ChatChannelAuthorBadge {
    static func showsDirectAuthor(in chat: TelegramChannelInfo?, author: TelegramChannelInfo?, displaysAuthor: Bool, isIncoming: Bool) -> Bool {
        guard displaysAuthor, isIncoming, case .group? = chat, case .broadcast? = author else {
            return false
        }
        return true
    }
}
