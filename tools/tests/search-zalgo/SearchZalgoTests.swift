import Foundation
import SwiftSignalKit
import XCTest

private typealias RenderedPeer = SearchPeer
private typealias Peer = SearchPeer
private typealias PeerId = Int
private typealias PeerStoryStats = Int
private typealias UnreadSearchBadge = Int
private typealias PeerStatusStringResult = Int
private typealias AdPeer = Int
private typealias MessageHistoryThreadData = Int
private typealias CombinedPeerReadState = Int
private typealias SeparatorBlockState = Int
private typealias TelegramGlobalPostSearchState = Int
private enum StoryListContext { typealias State = Int }
private enum SearchTags { typealias ListType = Int }
private enum EngineChatList { struct Item: Equatable { let index: Int } }
private enum ChatListSearchEntryStableId: Hashable {
    case localPeerId(Int), topic(Int), secretChat(Int), savedMessages, recentSearchPeerId(Int)
    case globalPeerId(Int), messageId(MessageId), topPeers, separator(Int), emptySearch, foundStories, disclaimer
}
private protocol Identifiable {
    associatedtype T: Hashable
    var stableId: T { get }
}
private struct SearchPeer: Equatable {
    let peerId: Int
    let id: Int
    func isEqual(_ other: Self) -> Bool { self == other }
}
private struct FoundPeer { let peer: SearchPeer; let subscribers: Int }
private struct AppearanceWrapperEntry<Entry: Equatable>: Equatable {
    let entry: Entry
    let appearance: Int
}

struct PeerID: Hashable { let namespace: Int; let id: Int }
struct MessageId: Hashable { let peerId: PeerID }
enum Namespaces { enum Peer { static let SecretChat = 3 } }
let servicePeerId = PeerID(namespace: 0, id: 1)
let verifyCodePeerId = PeerID(namespace: 0, id: 2)
struct RichTextMessageAttribute {}
struct TypingDraftMessageAttribute {}
struct TelegramMediaFile { var probablySticker = false; var isInstantVideo = false; var isMusic = false }
struct TelegramMediaImage {}
struct TelegramMediaWebpage {}
struct TelegramMediaPoll {}
struct Entity { enum Kind { case Spoiler }; let type: Kind }
struct Entities { let entities: [Entity] }
struct Message {
    var id = MessageId(peerId: PeerID(namespace: 0, id: 3))
    var stableVersion = 1
    var text: String
    var adAttribute: Int?
    var storyAttribute: Int?
    var isMediaSpoilered = false
    var containsSecretMedia = false
    var autoremoveAttribute: Int?
    var attributes: [Any] = []
    var textEntities: Entities?
    var media: [Any] = []
}

__SEARCH_ENTRY__

final class SearchZalgoTests: XCTestCase {
    func testLiveToggleReprojectsExistingRowsWithoutResubscribing() {
        let query = "👩🏽‍💻 match\u{202E}"
        let message = Message(text: "A\u{0301}\u{0308}\u{0327} " + query)
        let story = Message(id: .init(peerId: .init(namespace: 0, id: 4)), text: message.text, storyAttribute: 1)
        let protected = Message(id: .init(peerId: .init(namespace: 3, id: 5)), text: message.text)
        let custom = Message(id: .init(peerId: .init(namespace: 0, id: 6)), text: message.text, attributes: [RichTextMessageAttribute()])
        let entries: [ChatListSearchEntry] = [
            .message(message, query, nil, nil, 1), .message(story, query, nil, nil, 2),
            .message(protected, query, nil, nil, 3), .message(custom, query, nil, nil, 4), .foundStories(1, index: 5, query: query)
        ]
        var subscriptions = 0
        let searchItems = Signal<([ChatListSearchEntry], Bool, Bool, Int?, Int?), NoError> { subscriber in
            subscriptions += 1
            subscriber.putNext((entries, false, false, 10, 20))
            return EmptyDisposable
        }
        let filter = ValuePromise(false, ignoreRepeated: true)
        let appearanceSignal = Signal<Int, NoError>.single(0)
        let locationSignal = Signal<Int?, NoError>.single(1)
        let hideStoryIndicators = Signal<Bool, NoError>.single(false)
        let prepareQueue: Queue? = nil
        __SEARCH_PROJECTION__
        var snapshots: [[ChatListSearchEntry]] = []
        let disposable = transition.start(next: { snapshots.append($0.0.map(\.entry)) })
        filter.set(true)
        filter.set(true)
        filter.set(false)
        disposable.dispose()
        XCTAssertEqual(subscriptions, 1)
        XCTAssertEqual(snapshots.count, 3)
        guard snapshots.count == 3 else { return }
        XCTAssertEqual(snapshots[0], snapshots[2])
        XCTAssertNotEqual(snapshots[0][0], snapshots[1][0])
        XCTAssertEqual(snapshots[0].dropFirst(), snapshots[1].dropFirst())
        XCTAssertEqual(snapshots[0].map(\.stableId), snapshots[1].map(\.stableId))
        guard case let .message(projected, rawQuery, _, _, _, enabled) = snapshots[1][0] else {
            return XCTFail("Expected the same message row after toggling")
        }
        XCTAssertTrue(enabled)
        XCTAssertEqual(rawQuery, query)
        XCTAssertEqual(projected.text, message.text)
    }

    func testSnippetKeepsNativeHighlightAndUTF16Range() throws {
        let matched = "👩🏽‍💻 cafe"
        let original = "…a\u{1D185}\u{0301}\u{0308} " + matched + "\u{202E}…"
        let source = NSMutableAttributedString(string: original)
        let nativeHighlight = NSAttributedString.Key("NativeHighlight")
        let range = (original as NSString).range(of: matched)
        source.addAttribute(nativeHighlight, value: true, range: range)
        let transform = try XCTUnwrap(ChatListZalgoPreview.transform(enabled: true, message: Message(text: original), hasDraft: false))
        let display = try XCTUnwrap(transform(source))
        var highlightedRange = NSRange()
        XCTAssertEqual(display.attribute(nativeHighlight, at: range.location, effectiveRange: &highlightedRange) as? Bool, true)
        XCTAssertEqual(highlightedRange, range)
        XCTAssertEqual(display.attributedSubstring(from: range).string, matched)
        XCTAssertEqual(display.string, "…a\u{2060}\u{2060}\u{2060}\u{2060} " + matched + "\u{2060}…")
        XCTAssertEqual(display.length, source.length)
        XCTAssertEqual(source.string, original)
    }
}
