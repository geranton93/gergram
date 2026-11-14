import Foundation
import Postbox
import TelegramCore
import TGUIKit
import XCTest
@testable import ChatListUI

final class ChatListZalgoArchiveTests: XCTestCase {
    func testArchiveTrimmingPreservesExactMessageBoundaryAndNativeAttributes() throws {
        let prefix = "  First\rChat 👩\u{202E}\r"
        let body = "Caption\u{0301}\u{0308}\u{0327}\rhttps://example.com\u{202E}\n"
        let source = NSMutableAttributedString(string: prefix + body)
        let link = NSAttributedString.Key("testLink")
        let linkRange = (source.string as NSString).range(of: "https://example.com")
        source.addAttribute(link, value: "https://example.com", range: linkRange)
        let preview = ChatListZalgoPreview.trimmedArchivePreview(source, bodyOffset: prefix.utf16.count)
        XCTAssertTrue(preview.text.isEqual(to: source.trimmed))
        let offset = try XCTUnwrap(preview.bodyOffset)
        XCTAssertEqual(offset, prefix.utf16.count - 2)

        let transform = try XCTUnwrap(ChatListZalgoPreview.transform(enabled: true, message: message(text: body), hasDraft: false, prefixLength: offset))
        let display = try XCTUnwrap(transform(preview.text))
        XCTAssertEqual(display.string, "First\rChat 👩\u{202E}\rCaption\u{2060}\u{2060}\u{2060}\rhttps://example.com\u{2060}")
        XCTAssertEqual(display.length, preview.text.length)
        XCTAssertEqual(display.attribute(link, at: linkRange.location - 2, effectiveRange: nil) as? String, "https://example.com")
        XCTAssertEqual(source.string, prefix + body)
        XCTAssertNil(ChatListZalgoPreview.transform(enabled: false, message: message(text: body), hasDraft: false, prefixLength: offset))
    }

    func testArchiveWithoutSurvivingBodyDoesNotAcquireAPreviewOffset() {
        let source = NSAttributedString(string: "Archive\r\n")
        for offset in [nil, -1, source.length, source.length - 1] {
            let preview = ChatListZalgoPreview.trimmedArchivePreview(source, bodyOffset: offset)
            XCTAssertTrue(preview.text.isEqual(to: source.trimmed))
            XCTAssertNil(preview.bodyOffset)
        }

        let bodyOnly = NSAttributedString(string: "  Caption")
        let preview = ChatListZalgoPreview.trimmedArchivePreview(bodyOnly, bodyOffset: 0)
        XCTAssertEqual(preview.text.string, "Caption")
        XCTAssertEqual(preview.bodyOffset, 0)
    }

    private func message(text: String) -> Message {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(200))
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1),
                       globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1,
                       flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
                       author: nil, text: text, attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(),
                       associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }
}
