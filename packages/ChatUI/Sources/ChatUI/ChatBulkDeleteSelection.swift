import Foundation
import Postbox

enum ChatBulkDeleteSelection {
    static let limit = 100
    static let scanLimit = 1_000

    struct Scope: Equatable {
        let accountId: Int64
        let authorId: PeerId
        let peerId: PeerId
        let threadId: Int64?
    }

    enum DateFilter: CaseIterable {
        case all, pastWeek, pastMonth

        func range(endingAt timestamp: Int32) -> ClosedRange<Int64>? {
            switch self {
            case .all:
                return nil
            case .pastWeek:
                return (Int64(timestamp) - 7 * 86_400) ... Int64(timestamp)
            case .pastMonth:
                return (Int64(timestamp) - 30 * 86_400) ... Int64(timestamp)
            }
        }
    }

    enum MediaFilter: CaseIterable, Hashable {
        case all, photos, videos, voice, videoMessages, gifs, stickers
    }

    struct Candidate {
        let id: MessageId
        let authorId: PeerId?
        let threadId: Int64?
        let timestamp: Int32
        let version: UInt32
        let media: Set<MediaFilter>
    }

    struct Preview: Equatable {
        let scope: Scope
        fileprivate let dates: ClosedRange<Int64>?
        fileprivate let media: MediaFilter
        fileprivate let versions: [MessageId: UInt32]

        var ids: Set<MessageId> { Set(versions.keys) }

        func confirmedIds(in scope: Scope, candidates: [Candidate]) -> Set<MessageId>? {
            guard self.scope == scope,
                  case let .ready(current) = ChatBulkDeleteSelection.preview(
                      scope: scope, dates: dates, media: media,
                      candidates: candidates.filter { versions[$0.id] != nil }
                  ), current == self else { return nil }
            return ids
        }
    }

    enum Result: Equatable {
        case empty
        case limitExceeded
        case scanLimitExceeded
        case changed
        case ready(Preview)
    }

    static func preview(scope: Scope, dates: ClosedRange<Int64>?, media: MediaFilter, candidates: [Candidate]) -> Result {
        guard candidates.count <= scanLimit else { return .scanLimitExceeded }
        var versions: [MessageId: UInt32] = [:]
        for candidate in candidates {
            guard candidate.id.peerId == scope.peerId, candidate.authorId == scope.authorId,
                  candidate.threadId == scope.threadId,
                  dates?.contains(Int64(candidate.timestamp)) ?? true,
                  media == .all || candidate.media.contains(media) else { continue }
            if let version = versions[candidate.id], version != candidate.version {
                return .changed
            }
            versions[candidate.id] = candidate.version
            if versions.count > limit {
                return .limitExceeded
            }
        }
        guard !versions.isEmpty else { return .empty }
        return .ready(.init(scope: scope, dates: dates, media: media, versions: versions))
    }
}
