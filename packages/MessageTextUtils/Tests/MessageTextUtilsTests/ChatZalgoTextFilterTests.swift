import Foundation
import XCTest
@testable import MessageTextUtils

final class ChatZalgoTextFilterTests: XCTestCase {
    func testDisplayNamesRespectPreferenceAndPreserveOrdinaryScripts() {
        let displayName = "A\u{0301} Л\u{0301} 👩🏽‍💻 שלום"
        XCTAssertEqual(ChatZalgoTextFilter.displayName(displayName, enabled: true), displayName)
        let malformed = "N\u{0301}\u{0308}\u{0327}ame\u{202E}"
        XCTAssertEqual(ChatZalgoTextFilter.displayName(malformed, enabled: false), malformed)
        XCTAssertEqual(ChatZalgoTextFilter.displayName(malformed, enabled: true), "N\u{2060}\u{2060}\u{2060}ame\u{2060}")
    }

    func testOrdinaryMarksAndEmojiHaveNoPresentationOverride() {
        let text = "e\u{0301}\u{0323} का a\u{20DD} 👩🏽‍💻 שלום"
        XCTAssertNil(ChatZalgoTextFilter.presentation(for: NSAttributedString(string: text)))
    }

    func testReplacesOnlyRunsOfAtLeastThreeNonspacingMarks() throws {
        let text = "e\u{0301}\u{0308}\u{0327}\u{0323} a\u{0301}\u{0323} b\u{0301}\u{0308}\u{0327}"
        let display = try XCTUnwrap(ChatZalgoTextFilter.presentation(for: NSAttributedString(string: text)))
        XCTAssertEqual(display.string, "e\u{2060}\u{2060}\u{2060}\u{2060} a\u{0301}\u{0323} b\u{2060}\u{2060}\u{2060}")
        XCTAssertEqual(display.length, text.utf16.count)
    }

    func testMatchesOnlyTheReferenceDirectionControls() throws {
        let text = "\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}👩‍💻\u{2060}\u{200C}"
        let display = try XCTUnwrap(ChatZalgoTextFilter.presentation(for: NSAttributedString(string: text)))
        XCTAssertEqual(display.string, String(repeating: "\u{2060}", count: 12) + "👩‍💻\u{2060}\u{200C}")
    }

    func testSupplementaryMarksPreserveUTF16LengthAndAttributedRanges() throws {
        let text = "a\u{1D185}\u{0301}\u{0308}https://example.com 👋"
        let original = NSMutableAttributedString(string: text)
        let linkKey = NSAttributedString.Key("testLink")
        let markKey = NSAttributedString.Key("testMark")
        let url = "https://example.com"
        let linkRange = (text as NSString).range(of: url)
        original.addAttribute(linkKey, value: url, range: linkRange)
        original.addAttribute(markKey, value: "mark style", range: NSRange(location: 3, length: 2))

        let display = try XCTUnwrap(ChatZalgoTextFilter.presentation(for: original))
        XCTAssertEqual(original.string, text)
        XCTAssertEqual(display.string, "a\u{2060}\u{2060}\u{2060}\u{2060}https://example.com 👋")
        XCTAssertEqual(display.length, original.length)
        XCTAssertEqual(display.attributedSubstring(from: linkRange).string, url)
        XCTAssertEqual(display.attribute(linkKey, at: linkRange.location, effectiveRange: nil) as? String, url)
        XCTAssertEqual(display.attribute(markKey, at: 3, effectiveRange: nil) as? String, "mark style")
        XCTAssertNil(display.attribute(markKey, at: 2, effectiveRange: nil))
    }

    func testPreviewRangePreservesTheNativeTopicAndAuthorPrefix() throws {
        let prefix = "👩 Topic\u{202E}\nA\u{0301}\u{0308}\u{0327}: "
        let text = "a\u{1D185}\u{0301}\u{0308}https://example.com\u{202E}"
        let original = NSMutableAttributedString(string: prefix + text)
        let key = NSAttributedString.Key("testLink")
        let linkRange = (original.string as NSString).range(of: "https://example.com")
        original.addAttribute(key, value: "https://example.com", range: linkRange)
        let previewRange = NSRange(location: prefix.utf16.count, length: text.utf16.count)
        let display = try XCTUnwrap(ChatZalgoTextFilter.presentation(for: original, in: previewRange))
        XCTAssertEqual(display.string, prefix + "a\u{2060}\u{2060}\u{2060}\u{2060}https://example.com\u{2060}")
        XCTAssertEqual(display.length, original.length)
        XCTAssertEqual(display.attribute(key, at: linkRange.location, effectiveRange: nil) as? String, "https://example.com")
        XCTAssertEqual(original.string, prefix + text)
        XCTAssertNil(ChatZalgoTextFilter.presentation(for: original, in: NSRange(location: Int.max, length: 1)))
    }

    func testArchiveBodyEntitiesNeverResolveToDuplicatedPeerTitleText() {
        let caption = "👩 Date"
        let prefix = caption + "\r"
        let text = (prefix + "📎 " + caption) as NSString
        let offset = ChatListTextBodyOffset(value: prefix.utf16.count)
        let bodyRange = offset.entityRange(in: text, matching: caption)
        XCTAssertEqual(bodyRange.location, (prefix + "📎 ").utf16.count)
        XCTAssertEqual(text.substring(with: bodyRange), caption)
        XCTAssertEqual(offset.entityRange(in: text, matching: prefix).location, NSNotFound)
    }

    func testArchiveBodyEntitiesResolveToTheActualCaptionAfterAMatchingMediaIcon() {
        let caption = "📎"
        let prefix = "📎 Club\r📎 "
        let text = (prefix + caption) as NSString
        let offset = ChatListTextBodyOffset(value: "📎 Club\r".utf16.count)
        let range = offset.entityRange(in: text, matching: caption)
        XCTAssertEqual(range, NSRange(location: prefix.utf16.count, length: caption.utf16.count))
        XCTAssertEqual(offset.entityRange(in: text, matching: "📎 ").location, NSNotFound)
    }
}
