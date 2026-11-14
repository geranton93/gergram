import XCTest
@testable import EntertainmentUI

final class StickerPackIdentifierTests: XCTestCase {
    func testCopiesFullWidthUnsignedDecimalIDs() {
        XCTAssertEqual(StickerPackIdentifier(kind: .stickerSet, id: Int64.max)?.clipboardText, "9223372036854775807")
        XCTAssertEqual(StickerPackIdentifier(kind: .emojiSet, id: Int64.min)?.clipboardText, "9223372036854775808")
        XCTAssertEqual(StickerPackIdentifier(kind: .emoji, id: -1)?.clipboardText, "18446744073709551615")
    }

    func testOmitsUnavailableIDs() {
        XCTAssertNil(StickerPackIdentifier(kind: .stickerSet, id: 0))
        XCTAssertNil(StickerPackIdentifier(kind: .emojiSet, id: 0))
        XCTAssertNil(StickerPackIdentifier(kind: .emoji, id: 0))
    }

    func testKeepsPackAndEmojiActionsDistinct() {
        XCTAssertEqual(StickerPackIdentifier(kind: .stickerSet, id: 9)?.kind, .stickerSet)
        XCTAssertEqual(StickerPackIdentifier(kind: .emojiSet, id: 9)?.kind, .emojiSet)
        XCTAssertEqual(StickerPackIdentifier(kind: .emoji, id: 9)?.kind, .emoji)
    }
}
