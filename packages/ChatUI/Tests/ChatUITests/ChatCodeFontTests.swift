import AppKit
import CoreText
import InAppSettings
@testable import ChatUI
import TGUIKit
import XCTest

final class ChatCodeFontTests: XCTestCase {
    func testSystemUsesTheExistingCodeFontWithoutLookingUpAName() {
        let font = ChatCodeFont.resolve(.system, size: 15) { _, _ in
            XCTFail("System Default should use the existing code font")
            return nil
        }
        XCTAssertEqual(font, NSFont.code(15))
    }

    func testNativeChoicesAreFixedPitchAtTheRequestedSize() {
        for (choice, name) in [(ChatMonospaceFont.menlo, "Menlo-Regular"), (.monaco, "Monaco")] {
            let font = ChatCodeFont.resolve(choice, size: 16)
            let installed = NSFont(name: name, size: 16)
            XCTAssertEqual(font.fontName, installed?.fontName ?? NSFont.code(16).fontName)
            XCTAssertTrue(font.isFixedPitch)
            XCTAssertEqual(font.pointSize, 16)
            XCTAssertEqual(font.advancement(forGlyph: font.glyph(withName: "i")).width,
                           font.advancement(forGlyph: font.glyph(withName: "W")).width, accuracy: 0.01)
        }
    }

    func testMissingOrProportionalNamedFontUsesTheExistingCodeFont() {
        XCTAssertEqual(ChatCodeFont.resolve(.menlo, size: 13, find: { _, _ in nil }), NSFont.code(13))
        XCTAssertEqual(ChatCodeFont.resolve(.monaco, size: 17, find: { _, size in
            NSFont.systemFont(ofSize: size)
        }), NSFont.code(17))
    }

    func testCoreTextShapesMixedScriptsAndEmojiWithoutMissingGlyphs() {
        let text = "let value = 日本語 + مرحبا + 👩🏽‍💻"
        for choice in ChatMonospaceFont.allCases {
            let font = ChatCodeFont.resolve(choice, size: 15)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            let runs = CTLineGetGlyphRuns(line) as NSArray as! [CTRun]
            XCTAssertGreaterThan(CTLineGetTypographicBounds(line, nil, nil, nil), 0)
            XCTAssertTrue(runs.contains { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                return (attributes[kCTFontAttributeName] as? NSFont)?.fontName != font.fontName
            })
            for run in runs {
                var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                XCTAssertFalse(glyphs.contains(0))
            }
        }
    }

    func testPreferencePersistsAndFallsBackForUnknownValues() throws {
        let suite = "Gergram.Chat.MonospaceFont.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = ChatMonospaceFontPreferences(defaults: defaults)
        var changes: [ChatMonospaceFont] = []
        let subscription = preferences.signal.start(next: { changes.append($0) })
        preferences.set(.menlo)
        preferences.set(.menlo)
        XCTAssertEqual(ChatMonospaceFontPreferences(defaults: defaults).font, .menlo)
        preferences.set(.monaco)
        subscription.dispose()
        preferences.set(.system)

        XCTAssertEqual(changes, [.system, .menlo, .monaco])
        defaults.set("unavailable", forKey: "Gergram.Chat.MonospaceFont")
        XCTAssertEqual(ChatMonospaceFontPreferences(defaults: defaults).font, .system)
    }
}
