import Postbox
import TelegramCore

struct ForumSidebarSenderPreviewVisibility {
    typealias Row = ChatListSenderPreviewVisibility.Row
    typealias CandidateRows = ChatListSenderPreviewVisibility.CandidateRows

    struct Request: Equatable {
        let generation: Int
        let peerId: PeerId?
        let candidates: CandidateRows

        static let empty = Request(generation: 0, peerId: nil, candidates: [:])
    }

    private var request = Request.empty
    private var hiddenRows: Set<Row> = []

    static func rootPreview(in items: [EngineChatList.Item]) -> Message? {
        return items.lazy.flatMap(\.messages).max(by: { $0.index < $1.index })?._asMessage()
    }

    static func candidates(peerId: PeerId, rootMessage: Message?, items: [EngineChatList.Item], accountPeerId: PeerId) -> CandidateRows {
        var candidates: CandidateRows = [:]
        if let rootMessage {
            let senders = ChatListSenderPreviewVisibility.candidates(chatPeerId: peerId, messages: [rootMessage], accountPeerId: accountPeerId)
            if !senders.isEmpty {
                candidates[.init(id: .chatList(peerId), peerId: peerId)] = senders
            }
        }
        for item in items {
            guard case .forum = item.id, item.threadData != nil else { continue }
            let senders = ChatListSenderPreviewVisibility.candidates(
                chatPeerId: peerId,
                messages: item.messages.map { $0._asMessage() },
                accountPeerId: accountPeerId
            )
            if !senders.isEmpty {
                candidates[.init(id: item.id, peerId: peerId)] = senders
            }
        }
        return candidates
    }

    mutating func update(peerId: PeerId?, candidates: CandidateRows) -> Request? {
        guard request.peerId != peerId || request.candidates != candidates else { return nil }
        let previous = request
        request = Request(generation: previous.generation &+ 1, peerId: peerId, candidates: candidates)
        hiddenRows = Set(candidates.compactMap { row, senders in
            if previous.peerId != peerId || previous.candidates[row] != senders || hiddenRows.contains(row) {
                return row
            }
            return nil
        })
        return request
    }

    mutating func apply(_ request: Request, revealed: Set<PeerId>, hidden: Set<PeerId>) -> Bool {
        guard request.generation == self.request.generation, let peerId = request.peerId else { return false }
        let rows = Set(request.candidates.compactMap { row, senders in
            ChatListSenderPreviewVisibility.hidesPreview(chatPeerId: peerId, candidates: senders, revealed: revealed, hidden: hidden) ? row : nil
        })
        guard hiddenRows != rows else { return false }
        hiddenRows = rows
        return true
    }

    func hidesPreview(_ id: EngineChatList.Item.Id, peerId: PeerId) -> Bool {
        return hiddenRows.contains(.init(id: id, peerId: peerId))
    }
}
