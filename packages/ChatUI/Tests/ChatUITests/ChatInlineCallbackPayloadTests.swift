import Foundation
import XCTest
@testable import ChatUI

final class ChatInlineCallbackPayloadTests: XCTestCase {
    func testPreservesUTF8AndEmptyPayloads() {
        let text = "next:тест\npage\t2"
        XCTAssertEqual(ChatInlineCallbackPayload(data: Data(text.utf8)), .text(text))
        XCTAssertEqual(ChatInlineCallbackPayload(data: Data()), .text(""))
    }

    func testBinaryAndControlBytesRoundTripAsBase64() {
        let samples = [Data([0xff, 0xf0, 0x08]), Data([0]), Data("direction\u{202e}".utf8)]
        for data in samples {
            guard case let .base64(encoded) = ChatInlineCallbackPayload(data: data) else {
                XCTFail("Expected a binary-safe representation")
                continue
            }
            XCTAssertEqual(Data(base64Encoded: encoded), data)
        }
    }
}
