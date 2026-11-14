public enum GergramSettingsRoute: String {
    case messageContextMenu = "general/message-context-menu"
    case transcriptionLanguage = "general/on-device-transcription-language"
    case messageBubbleCorners = "appearance/message-bubble-corners"
    case avatarCorners = "appearance/avatar-corners"
    case locallyHiddenSenders = "privacy/locally-hidden-senders"
    case messageFilters = "privacy/message-filters"
    case localMessageArchive = "privacy/local-message-archive"

    public static func recognizesScheme(_ url: String) -> Bool {
        let scheme = "gergram:"
        return url.prefix(scheme.count).lowercased() == scheme
    }

    public init?(url: String) {
        let prefix = "gergram://settings/"
        guard url.prefix(prefix.count).lowercased() == prefix else { return nil }
        self.init(rawValue: String(url.dropFirst(prefix.count)))
    }
}
