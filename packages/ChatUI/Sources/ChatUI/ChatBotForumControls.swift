enum ChatBotForumNavigationAction: Equatable {
    case hidden
    case search
    case more
}

enum ChatBotForumControls {
    static func showsStart(isBot: Bool, isScheduled: Bool, historyCount: Int?, threadId: Int64?, isBlocked: Bool) -> Bool {
        return isBot && !isScheduled && (isBlocked || (historyCount == 0 && threadId == nil))
    }

    static func startPayloadPreview(_ payload: String) -> String? {
        let prefix = payload.utf16.prefix(20)
        guard !prefix.isEmpty else { return nil }

        var end = prefix.endIndex
        while end != prefix.startIndex {
            if let characterBoundary = String.Index(end, within: payload) {
                return String(payload[..<characterBoundary])
            }
            prefix.formIndex(before: &end)
        }
        return "…"
    }

    static func navigationAction(hasForum: Bool, isPreview: Bool, isPinned: Bool, historyCount: Int?, threadId: Int64?) -> ChatBotForumNavigationAction? {
        guard hasForum else {
            return nil
        }
        if isPreview || isPinned {
            return .hidden
        }
        if threadId != nil {
            return .more
        }
        return (historyCount ?? 0) > 0 ? .search : .hidden
    }
}
