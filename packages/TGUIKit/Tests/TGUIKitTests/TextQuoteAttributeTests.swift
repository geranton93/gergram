import Cocoa
import XCTest
@testable import TGUIKit

final class TextQuoteAttributeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func header(_ title: String) -> (TextNodeLayout, TextNode) {
        TextNode.layoutText(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12)]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left)
    }

    func testEqualityIncludesFoldingAndHeaderStateAndHashesAgree() {
        let title = header("Swift")
        let original = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: title, collapsable: true)
        let same = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: title, collapsable: true)
        XCTAssertEqual(original, same)
        XCTAssertEqual(original.hash, same.hash)
        XCTAssertEqual(NSSet(array: [original, same]).count, 1)
        for different in [
            TextViewBlockQuoteData(id: 2, colors: .init(main: .blue), isCode: true, header: title, collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .red), isCode: true, header: title, collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: false, header: title, collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, space: 8, header: title, collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: nil, collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: header("Python"), collapsable: true),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: title, collapsable: false),
            TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: title, collapsable: true, fillsBackground: false)
        ] {
            XCTAssertNotEqual(original, different)
            XCTAssertEqual(NSSet(array: [original, different]).count, 2)
        }
        let noHeader = TextViewBlockQuoteData(id: 3, colors: .init(main: .blue))
        let sameNoHeader = TextViewBlockQuoteData(id: 3, colors: .init(main: .blue))
        XCTAssertEqual(noHeader, sameNoHeader)
        XCTAssertEqual(noHeader.hash, sameNoHeader.hash)
    }

    func testFoundationPreservesDistinctQuoteAttributesAndRunBoundaries() {
        let title = header("Swift")
        var retained: [NSAttributedString] = []
        for index in 0..<1024 {
            let collapsable = index % 2 == 0
            let hasHeader = index % 3 == 0
            let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), isCode: true, header: hasHeader ? title : nil, collapsable: collapsable)
            let string = NSAttributedString(string: "quoted", attributes: [.font: NSFont.systemFont(ofSize: 14), TextInputAttributes.quote: quote])
            let recovered = string.attribute(TextInputAttributes.quote, at: 0, effectiveRange: nil) as! TextViewBlockQuoteData
            XCTAssertEqual(recovered.collapsable, collapsable)
            XCTAssertEqual(recovered.header != nil, hasHeader)
            retained.append(string)
        }
        let joined = NSMutableAttributedString()
        joined.append(retained[0])
        joined.append(retained[1])
        var runs = 0
        joined.enumerateAttribute(TextInputAttributes.quote, in: NSRange(location: 0, length: joined.length)) { _, _, _ in runs += 1 }
        XCTAssertEqual(runs, 2)
        let layout = TextViewLayout(retained[0])
        layout.measure(width: 200)
        XCTAssertTrue(layout.blockCollapsable)
        XCTAssertNotNil(layout.blockQuotes.first?.header)
        let other = TextViewLayout(retained[1])
        other.measure(width: 200)
        XCTAssertFalse(other.blockCollapsable)
        XCTAssertNil(other.blockQuotes.first?.header)
    }

    func testSimplifiedQuoteKeepsTextAndOutlineWithoutColoredFill() throws {
        func render(fillsBackground: Bool) throws -> (TextViewLayout, Data) {
            let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), fillsBackground: fillsBackground)
            let string = NSAttributedString(string: "A quoted passage", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.black,
                TextInputAttributes.quote: quote
            ])
            let layout = TextViewLayout(string)
            layout.measure(width: 180)
            let view = TextView(frame: NSRect(origin: .zero, size: layout.layoutSize))
            view.update(layout)
            view.layout()
            let context = try XCTUnwrap(CGContext(
                data: nil, width: 360, height: 200, bitsPerComponent: 8, bytesPerRow: 1440,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.scaleBy(x: 2, y: 2)
            view.draw(view.drawingLayer, in: context)
            return (layout, Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height))
        }

        let (regular, regularPixels) = try render(fillsBackground: true)
        let (simple, simplePixels) = try render(fillsBackground: false)
        let regularQuote = try XCTUnwrap(regular.blockQuotes.first)
        let simpleQuote = try XCTUnwrap(simple.blockQuotes.first)
        XCTAssertTrue(regularQuote.fillsBackground)
        XCTAssertFalse(simpleQuote.fillsBackground)
        XCTAssertEqual(simpleQuote.frame, regularQuote.frame)
        XCTAssertEqual(simpleQuote.colors, regularQuote.colors)
        XCTAssertEqual(simple.attributedString.string, regular.attributedString.string)
        let regularAlpha = stride(from: 3, to: regularPixels.count, by: 4)
        XCTAssertTrue(regularAlpha.contains { regularPixels[$0] > 0 && simplePixels[$0] == 0 })
        XCTAssertTrue(regularAlpha.contains { regularPixels[$0] == 255 && simplePixels[$0] == 255 })
    }

}
