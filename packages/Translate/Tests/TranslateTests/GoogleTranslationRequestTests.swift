import Foundation
import XCTest
@testable import Translate

final class GoogleTranslationRequestTests: XCTestCase {
    func testQueryPreservesTextWithoutInterpretingDelimiters() throws {
        let text = "Привіт &tl=de + #topic = 🐱\n100%"
        let url = try XCTUnwrap(GoogleTranslationRequest.url(text: text, from: nil, to: "zh-TW"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "translate.googleapis.com")
        XCTAssertNil(components.fragment)
        XCTAssertEqual(query.filter { $0.name == "q" }.map(\.value), [text])
        XCTAssertEqual(query.filter { $0.name == "tl" }.map(\.value), ["zh-TW"])
        XCTAssertEqual(query.first { $0.name == "sl" }?.value, "auto")
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") == true)
    }

    func testReadsSegmentsInOrderAndSupportsAbsentDetection() throws {
        let detected = try XCTUnwrap(GoogleTranslationRequest.result(from: Data(#"[[["First ","a"],["second","b"]],null,"uk"]"#.utf8)))
        XCTAssertEqual(detected.result, "First second")
        XCTAssertEqual(detected.detect, "uk")

        let short = try XCTUnwrap(GoogleTranslationRequest.result(from: Data(#"[[["hello","bonjour"]]]"#.utf8)))
        XCTAssertEqual(short.result, "hello")
        XCTAssertNil(short.detect)
    }

    func testRejectsMalformedAndEmptyResponses() {
        for response in ["not json", "[]", #"[null,null,"en"]"#, #"[[[null,"original"]],null,"en"]"#] {
            XCTAssertNil(GoogleTranslationRequest.result(from: Data(response.utf8)))
        }
    }
}
