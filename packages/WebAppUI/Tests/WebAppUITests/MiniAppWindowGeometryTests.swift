import CoreGraphics
import Foundation
import InAppSettings
import XCTest
@testable import WebAppUI

final class MiniAppWindowGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 24, width: 1440, height: 900)
    private let parent = CGRect(x: 120, y: 60, width: 900, height: 800)

    func testIndependentPreferencesPersistAndDefaultToStandardSize() throws {
        let suiteName = "MiniAppWindowGeometryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MiniAppWindowSizePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnlarged(.width))
        XCTAssertFalse(preferences.isEnlarged(.height))

        preferences.setEnlarged(true, for: .width)
        let reopened = MiniAppWindowSizePreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertTrue(reopened.isEnlarged(.width))
        XCTAssertFalse(reopened.isEnlarged(.height))

        reopened.setEnlarged(true, for: .height)
        reopened.setEnlarged(false, for: .width)
        XCTAssertFalse(preferences.isEnlarged(.width))
        XCTAssertTrue(preferences.isEnlarged(.height))
    }

    func testIndependentDimensionsAndResizeMinimum() {
        let standard = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: screen, largerWidth: false, largerHeight: false)
        let wider = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: screen, largerWidth: true, largerHeight: false)
        let taller = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: screen, largerWidth: false, largerHeight: true)
        let enlarged = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: screen, largerWidth: true, largerHeight: true)
        XCTAssertEqual(standard.frame.size, CGSize(width: 420, height: 714))
        XCTAssertEqual(wider.frame.size, CGSize(width: 512, height: 714))
        XCTAssertEqual(taller.frame.size, CGSize(width: 420, height: 782))
        XCTAssertEqual(enlarged.frame.size, CGSize(width: 512, height: 782))
        XCTAssertEqual(enlarged.minimumSize, standard.frame.size)
        XCTAssertEqual(enlarged.frame.midX, parent.midX)
        XCTAssertEqual(enlarged.frame.midY, parent.midY)
    }

    func testVisibleFrameClampsAnOversizedWindowOnASecondaryScreen() {
        let smallScreen = CGRect(x: -520, y: 60, width: 380, height: 580)
        let parent = CGRect(x: -530, y: 40, width: 900, height: 700)
        let geometry = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: smallScreen, largerWidth: true, largerHeight: true)
        XCTAssertEqual(geometry.frame, smallScreen)
        XCTAssertEqual(geometry.minimumSize, smallScreen.size)
    }

    func testDockInsetKeepsPreferredSizeAndMovesTheWindowWithinTheScreen() {
        let screen = CGRect(x: -1120, y: 48, width: 1000, height: 810)
        let parent = CGRect(x: -1260, y: -30, width: 360, height: 550)
        let geometry = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: screen, largerWidth: true, largerHeight: true)
        XCTAssertEqual(geometry.frame, CGRect(x: -1120, y: 48, width: 512, height: 782))
    }

    func testUnavailableScreenStillCentersThePreferredSize() {
        let geometry = MiniAppWindowGeometry(parentFrame: parent, visibleFrame: nil, largerWidth: true, largerHeight: false)
        XCTAssertEqual(geometry.frame, CGRect(x: 314, y: 103, width: 512, height: 714))
    }
}
