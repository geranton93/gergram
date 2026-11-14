import Foundation
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatRegexFilterProjectionTests: XCTestCase {
    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))
    private let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(200))

    private func entry(_ id: Int32, action: ReplyMarkupButtonAction? = nil, media: [Media] = []) -> MessageHistoryEntry {
        let markup = action.map { action in
            ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: [ReplyMarkupButton(title: "Open", titleWhenForwarded: nil, action: action, style: nil)])], flags: [], placeholder: nil)
        }
        let message = Message(stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: channelId, namespace: Namespaces.Message.Cloud, id: id),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id, flags: [.Incoming], tags: [], globalTags: [],
            localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "Message", attributes: markup.map { [$0] } ?? [], media: media,
            peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:],
            associatedThreadInfo: nil, associatedStories: [:])
        return MessageHistoryEntry(message: message, isRead: false, location: nil, monthLocation: nil,
                                   attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false))
    }

    private func assertHidden(_ entries: [MessageHistoryEntry], by rule: LocalMessageFilterRule, expected: [MessageHistoryEntry], file: StaticString = #filePath, line: UInt = #line) {
        let completed = expectation(description: "Regex history projection")
        let disposable = ChatRegexFilterProjection.hiddenItems(entries: entries, rules: [rule], accountPeerId: accountPeerId).start(next: { hidden in
            XCTAssertEqual(hidden, Set(expected.map { ChatLocalHiddenItem($0.message) }), file: file, line: line)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 2.0)
        disposable.dispose()
    }

    func testMatchesAuthAndWebViewURLsAndInlineAndCopyPayloads() {
        let auth = entry(1, action: .urlAuth(url: "https://test.invalid/auth", buttonId: 42))
        let webView = entry(2, action: .openWebView(url: "https://test.invalid/web", simple: false))
        let simple = entry(3, action: .openWebView(url: "https://test.invalid/simple", simple: true))
        let query = entry(4, action: .switchInline(samePeer: true, query: "sample-query", peerTypes: []))
        let copy = entry(5, action: .copyText(payload: "payload-to-copy"))
        let control = entry(6, action: .text)
        let entries = [auth, webView, simple, query, copy, control]
        assertHidden(entries, by: .init(pattern: #"<button>Open https://test\.invalid/(auth|web|simple)</button>"#), expected: [auth, webView, simple])
        assertHidden(entries, by: .init(pattern: "<button>Open sample-query</button>"), expected: [query])
        assertHidden(entries, by: .init(pattern: "<button>Open payload-to-copy</button>"), expected: [copy])
    }

    func testMatchesUserProfileIdentifierAndDistinguishesQuizFlags() {
        let profile = entry(1, action: .openUserProfile(peerId: accountPeerId))
        let invalidProfile = entry(2, action: .openUserProfile(peerId: channelId))
        let quiz = entry(3, action: .setupPoll(isQuiz: true))
        let poll = entry(4, action: .setupPoll(isQuiz: false))
        let unspecified = entry(5, action: .setupPoll(isQuiz: nil))
        let entries = [profile, invalidProfile, quiz, poll, unspecified]
        assertHidden(entries, by: .init(pattern: #"<button>Open \d+</button>"#), expected: [profile])
        assertHidden(entries, by: .init(pattern: #"<button>Open \x{0001}</button>"#), expected: [quiz])
        assertHidden(entries, by: .init(pattern: #"<button>Open \x{0000}</button>"#), expected: [poll])
        assertHidden(entries, by: .init(pattern: "<button>Open </button>"), expected: [invalidProfile, unspecified])
    }

    func testDistinguishesStoryMentionsAndInvoiceMediaPreviews() {
        let storyId = StoryId(peerId: channelId, id: 1)
        let story = TelegramMediaStory(storyId: storyId, isMention: false)
        let mention = TelegramMediaStory(storyId: storyId, isMention: true)
        func invoice(_ media: TelegramExtendedMedia?) -> TelegramMediaInvoice {
            TelegramMediaInvoice(title: "Invoice", description: "", photo: nil, receiptMessageId: nil, currency: "USD", totalAmount: 100,
                startParam: "", extendedMedia: media, subscriptionPeriod: nil, flags: [], version: TelegramMediaInvoice.lastVersion)
        }
        let ordinaryStory = entry(1, media: [story])
        let storyMention = entry(2, media: [mention])
        let preview = entry(3, media: [invoice(.preview(dimensions: nil, immediateThumbnailData: nil, videoDuration: nil))])
        let resolved = entry(4, media: [invoice(.full(media: story))])
        let unextended = entry(5, media: [invoice(nil)])
        let entries = [ordinaryStory, storyMention, preview, resolved, unextended]
        assertHidden(entries, by: .init(pattern: "<type>23</type>"), expected: [ordinaryStory])
        assertHidden(entries, by: .init(pattern: "<type>24</type>"), expected: [storyMention])
        assertHidden(entries, by: .init(pattern: "<type>20</type>"), expected: [preview])
        assertHidden(entries, by: .init(pattern: "<type>0</type>"), expected: [resolved, unextended])
    }

    func testOversizedButtonPayloadsKeepMessagesVisibleEvenForReversedRules() {
        let large = String(repeating: "x", count: LocalMessageFilterEvaluation.maximumInputLength + 1)
        let oversizedQuery = entry(1, action: .switchInline(samePeer: false, query: large, peerTypes: []))
        let oversizedCallback = entry(2, action: .callback(requiresPassword: false, data: MemoryBuffer(data: Data(large.utf8))))
        let control = entry(3, action: .copyText(payload: "Ordinary payload"))
        assertHidden([oversizedQuery, oversizedCallback, control], by: .init(pattern: "unmatched", isReversed: true), expected: [control])
    }
}
