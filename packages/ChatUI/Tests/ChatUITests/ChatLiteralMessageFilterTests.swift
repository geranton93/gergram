import InAppSettings
import XCTest
@testable import ChatUI

final class ChatLiteralMessageFilterTests: XCTestCase {
    func testSelectedMetacharactersBecomeLiteralICUPattern() throws {
        let selection = "Price [1].* \\E"
        let literal = try XCTUnwrap(ChatLiteralMessageFilter(selectedText: selection, originalText: "New \(selection) today"))
        let evaluation = try XCTUnwrap(LocalMessageFilterEvaluation())
        evaluation.prepare([LocalMessageFilterRule(pattern: literal.pattern, isCaseInsensitive: true)])
        XCTAssertTrue(evaluation.shouldHide("price [1].* \\e"))
        XCTAssertFalse(evaluation.shouldHide("Price 1xyz E"))
        XCTAssertEqual(literal.text, selection)
    }

    func testSelectionMustComeFromOriginalTextAndFitEscapedBudget() {
        XCTAssertNil(ChatLiteralMessageFilter(selectedText: "Rendered translation", originalText: "Original"))
        XCTAssertNil(ChatLiteralMessageFilter(selectedText: "  \n", originalText: "  \n"))
        let longSelection = String(repeating: ".", count: 129)
        XCTAssertNil(ChatLiteralMessageFilter(selectedText: longSelection, originalText: longSelection))
    }
}
