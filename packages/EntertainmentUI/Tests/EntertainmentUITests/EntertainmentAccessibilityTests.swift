import Cocoa
import XCTest
@testable import EntertainmentUI

final class EntertainmentAccessibilityTests: XCTestCase {
    func testPreviewAndPrimaryPressPerformSeparateActions() throws {
        let cells = EntertainmentAccessibilityCells()
        let view = NSView()
        var presses = 0
        var previews = 0
        let cell = EntertainmentAccessibilityCell(
            id: AnyHashable(1), label: "Test emoji", frame: .zero,
            alternateAction: EntertainmentAccessibilityAction(name: "Preview Emoji", perform: {
                previews += 1
                return true
            }),
            press: { presses += 1 }
        )

        let element = try XCTUnwrap(cells.elements(for: [cell], in: view).first as? EntertainmentAccessibilityCellElement)
        let action = try XCTUnwrap(element.accessibilityCustomActions()?.first)
        XCTAssertEqual(action.name, "Preview Emoji")
        XCTAssertEqual(action.handler?(), true)
        XCTAssertEqual(previews, 1)
        XCTAssertEqual(presses, 0)

        XCTAssertTrue(element.accessibilityPerformPress())
        XCTAssertEqual(previews, 1)
        XCTAssertEqual(presses, 1)
    }

    func testReusedElementRemovesAnUnavailablePreviewAction() throws {
        let cells = EntertainmentAccessibilityCells()
        let view = NSView()
        let emoji = EntertainmentAccessibilityCell(
            id: AnyHashable(1), label: "Test emoji", frame: .zero,
            alternateAction: EntertainmentAccessibilityAction(name: "Preview Emoji", perform: { false }),
            press: {}
        )
        let element = try XCTUnwrap(cells.elements(for: [emoji], in: view).first as? EntertainmentAccessibilityCellElement)
        let action = try XCTUnwrap(element.accessibilityCustomActions()?.first)
        XCTAssertEqual(action.handler?(), false)

        let ordinary = EntertainmentAccessibilityCell(id: AnyHashable(1), label: "Ordinary emoji", frame: .zero, press: {})
        let reused = try XCTUnwrap(cells.elements(for: [ordinary], in: view).first as? EntertainmentAccessibilityCellElement)
        XCTAssertTrue(reused === element)
        XCTAssertNil(reused.accessibilityCustomActions())
    }

    func testRemovedElementCannotPerformItsOldActions() throws {
        let cells = EntertainmentAccessibilityCells()
        let view = NSView()
        let cell = EntertainmentAccessibilityCell(
            id: AnyHashable(1), label: "Test emoji", frame: .zero,
            alternateAction: EntertainmentAccessibilityAction(name: "Preview Emoji", perform: { XCTFail("Removed preview ran"); return false }),
            press: { XCTFail("Removed press ran") }
        )

        let element = try XCTUnwrap(cells.elements(for: [cell], in: view).first as? EntertainmentAccessibilityCellElement)
        XCTAssertTrue(cells.elements(for: [], in: view).isEmpty)
        XCTAssertNil(element.accessibilityCustomActions())
        XCTAssertFalse(element.accessibilityPerformPress())
    }
}
