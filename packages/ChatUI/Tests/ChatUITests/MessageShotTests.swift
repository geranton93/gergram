import AppKit
import ColorPalette
import XCTest
@testable import ChatUI

final class MessageShotTests: XCTestCase {
    func testSpoilerRedactionMergesOverlappingAndAdjacentRanges() {
        let source = "left secret right"
        let redaction = MessageShotRenderer.SpoilerRedaction(text: source, spoilerRanges: [9..<11, 5..<9, 5..<7, 8..<9])

        XCTAssertEqual(redaction.text, "left •••••• right")
        XCTAssertEqual(redaction.text.utf16.count, source.utf16.count)
        XCTAssertTrue(redaction.permitsEntity(in: 0..<4))
        XCTAssertTrue(redaction.permitsEntity(in: 12..<17))
        XCTAssertFalse(redaction.permitsEntity(in: 4..<6))
        XCTAssertFalse(redaction.permitsEntity(in: 10..<12))
        XCTAssertFalse(redaction.permitsEntity(in: 5..<11))
    }

    func testSpoilerRedactionMasksCompleteComposedCharacters() {
        let source = "a💡e\u{0301}b"
        let redaction = MessageShotRenderer.SpoilerRedaction(text: source, spoilerRanges: [2..<3, 4..<5])

        XCTAssertEqual(redaction.text, "a••••b")
        XCTAssertEqual(redaction.text.utf16.count, source.utf16.count)
        XCTAssertFalse(redaction.permitsEntity(in: 1..<2))
        XCTAssertFalse(redaction.permitsEntity(in: 3..<4))
        XCTAssertTrue(redaction.permitsEntity(in: 5..<6))
    }

    func testSpoilerRedactionMasksAllTextWhenAnOffsetIsInvalid() {
        let source = "never display the original text"
        for invalidRange in [-1..<4, 1..<100, 3..<3, Int.min..<Int.max] {
            let redaction = MessageShotRenderer.SpoilerRedaction(text: source, spoilerRanges: [0..<2, invalidRange])
            XCTAssertEqual(redaction.text, String(repeating: "•", count: source.utf16.count))
            XCTAssertFalse(redaction.permitsEntity(in: 4..<8))
            XCTAssertFalse(redaction.permitsEntity(in: invalidRange))
        }
    }

    func testDifferentSpoilerContentsWithTheSameLengthRenderIdentically() throws {
        func png(_ source: String) throws -> Data {
            let redaction = MessageShotRenderer.SpoilerRedaction(text: source, spoilerRanges: [7..<13])
            let row = MessageShotRenderer.Row(header: text("Author"), body: text(redaction.text), background: .white)
            return try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        }

        XCTAssertEqual(try png("Public secret."), try png("Public hidden."))
    }

    func testReplyExcerptCompactsWhitespaceAndBoundsComposedCharacters() {
        XCTAssertEqual(MessageShotRenderer.Reply.excerpt(source: "  First\n\tsecond  "), "First second")
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: " \n "))
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: String(repeating: "x", count: 16_001)))

        let prefix = String(repeating: "a", count: 138)
        XCTAssertEqual(MessageShotRenderer.Reply.excerpt(source: prefix + "💡trailing"), prefix + "…")
    }

    func testReplyQuoteMatchesTheCurrentUTF16SourceWithoutSubstitutingCopiedText() {
        let source = "a💡 e\u{0301} secret"
        XCTAssertEqual(MessageShotRenderer.Reply.excerpt(source: source, quote: "💡", quoteOffset: 1), "💡")
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: source, quote: "💡", quoteOffset: 2))
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: source, quote: "é", quoteOffset: 4))
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: source, quote: "hidden", quoteOffset: 7))
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: source, quote: "secret", quoteOffset: nil))
        XCTAssertNil(MessageShotRenderer.Reply.excerpt(source: source, quote: "secret", quoteOffset: Int.max))
    }

    func testReplyAddsInsetAccentAndHeightToTheMessageCard() throws {
        let reply = MessageShotRenderer.Reply(title: text("Reply to a sender"), excerpt: text("Current source"), accent: .red)
        let baseline = MessageShotRenderer.Row(header: text("Author"), body: text("Body"), background: .white)
        let row = MessageShotRenderer.Row(header: baseline.header, body: baseline.body, background: .white, reply: reply)
        let withoutReply = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(MessageShotRenderer.png(rows: [baseline], background: nil))))
        let withReply = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))))

        XCTAssertEqual(withReply.pixelsWide, withoutReply.pixelsWide)
        XCTAssertGreaterThan(withReply.pixelsHigh, withoutReply.pixelsHigh)
        let accent = (0 ..< withReply.pixelsHigh).compactMap { withReply.colorAt(x: 58, y: $0)?.usingColorSpace(.deviceRGB) }
        XCTAssertTrue(accent.contains { $0.redComponent > $0.greenComponent + 0.3 && $0.redComponent > $0.blueComponent + 0.3 }, "\(accent.prefix(20))")
    }

    func testReplyTextCountsTowardExportBudget() {
        let reply = MessageShotRenderer.Reply(title: text("Author"), excerpt: text(String(repeating: "x", count: 16_000)), accent: .red)
        let row = MessageShotRenderer.Row(header: text(""), body: text(""), background: .white, reply: reply)
        XCTAssertNil(MessageShotRenderer.png(rows: [row], background: nil))
    }

    func testTimestampPreferenceDefaultsToVisibleAndPersistsBothValues() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertTrue(options.showsTimestamps)

        options.showsTimestamps = false
        options.save(to: defaults)
        let reader = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertFalse(MessageShotOptions(defaults: reader).showsTimestamps)

        options.showsTimestamps = true
        options.save(to: defaults)
        XCTAssertTrue(MessageShotOptions(defaults: reader).showsTimestamps)
    }

    func testHeaderOmitsTimestampAndSeparatorsWhenHidden() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertEqual(options.headerTitle(author: "Author", timestamp: "Date"), "Author • Date")
        XCTAssertEqual(options.headerTitle(author: nil, timestamp: "Date"), "Date")

        options.showsTimestamps = false
        XCTAssertEqual(options.headerTitle(author: "Author", timestamp: "Date"), "Author")
        XCTAssertEqual(options.headerTitle(author: nil, timestamp: "Date"), "")
    }

    func testHeaderDecorationsDefaultToVisibleAndPersistIndependentlyOfTimestamps() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertTrue(options.showsHeaderDecorations)
        XCTAssertEqual(options.headerDecoration("  Channel\n badge ", foreground: .white, background: .black)?.label, "Channel badge")
        XCTAssertNil(options.headerDecoration(" \t ", foreground: .white, background: .black))
        XCTAssertNil(options.headerDecoration(String(repeating: "a", count: 129), foreground: .white, background: .black))

        options.showsHeaderDecorations = false
        options.save(to: defaults)
        options = MessageShotOptions(defaults: defaults)
        XCTAssertFalse(options.showsHeaderDecorations)
        XCTAssertNil(options.headerDecoration("Channel", foreground: .white, background: .black))
        XCTAssertEqual(options.headerTitle(author: "Sender", timestamp: "Date"), "Sender • Date")
    }

    func testHiddenHeaderDecorationMatchesUndecoratedExport() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var options = MessageShotOptions(defaults: defaults)
        let header = text(options.headerTitle(author: "Sender", timestamp: "Date"))
        let body = text("Caption")
        func png(_ decoration: MessageShotRenderer.HeaderDecoration?) throws -> Data {
            let row = MessageShotRenderer.Row(header: header, headerDecoration: decoration, body: body, background: .white)
            return try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        }

        let visible = try png(options.headerDecoration("Channel", foreground: .white, background: .black))
        options.showsHeaderDecorations = false
        let hidden = try png(options.headerDecoration("Channel", foreground: .white, background: .black))
        XCTAssertEqual(hidden, try png(nil))
        XCTAssertNotEqual(visible, hidden)
    }

    func testLongHeaderDecorationHasBoundedWidthAndTruncatesBeforeHiddenText() throws {
        let common = String(repeating: "W", count: 50)
        func png(_ label: String) throws -> Data {
            let decoration = MessageShotRenderer.HeaderDecoration(label: label, foreground: .white, background: .red)
            let row = MessageShotRenderer.Row(header: text("Sender • Date"), headerDecoration: decoration, body: text("Body"), background: .black)
            return try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        }
        let pngWithBadge = try png(common + " left")
        XCTAssertEqual(pngWithBadge, try png(common + " right"))
        let image = try XCTUnwrap(NSBitmapImageRep(data: pngWithBadge))
        func isRed(_ x: Int, _ y: Int) -> Bool {
            guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.3
        }
        let redColumns = (0 ..< image.pixelsWide).filter { x in (55 ... 95).contains { isRed(x, $0) } }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(redColumns.first), (532 - 140) * 2)
        XCTAssertLessThan(try XCTUnwrap(redColumns.last), 532 * 2)
        XCTAssertGreaterThan(redColumns.count, 250)
    }

    func testHeaderDecorationUsesSuppliedContrastColorsInBothPalettes() throws {
        for (foreground, background, card) in [
            (NSColor.white, NSColor.black, NSColor.white),
            (NSColor.black, NSColor.white, NSColor.black)
        ] {
            let decoration = MessageShotRenderer.HeaderDecoration(label: "CHANNEL", foreground: foreground, background: background)
            let row = MessageShotRenderer.Row(header: text(""), headerDecoration: decoration, body: text(""), background: card)
            let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))))
            let pixels = (950 ... 1040).flatMap { x in
                (64 ... 80).compactMap { image.colorAt(x: x, y: $0)?.usingColorSpace(.deviceRGB)?.redComponent }
            }
            XCTAssertTrue(pixels.contains { $0 < 0.1 })
            XCTAssertTrue(pixels.contains { $0 > 0.9 })
        }
    }

    func testBackgroundDefaultsToVisibleAndPersistsIndependentlyOfTimestamps() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "gergram.messageShot.showsTimestamps")

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertTrue(options.showsBackground)
        XCTAssertFalse(options.showsTimestamps)

        options.showsBackground = false
        options.save(to: defaults)
        let reader = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var savedOptions = MessageShotOptions(defaults: reader)
        XCTAssertFalse(savedOptions.showsBackground)
        XCTAssertFalse(savedOptions.showsTimestamps)

        savedOptions.showsTimestamps = true
        savedOptions.save(to: reader)
        options = MessageShotOptions(defaults: defaults)
        XCTAssertFalse(options.showsBackground)
        XCTAssertTrue(options.showsTimestamps)

        options.showsBackground = true
        options.save(to: defaults)
        XCTAssertTrue(MessageShotOptions(defaults: reader).showsBackground)
    }

    func testTransparentCanvasPreservesMessageCardAndImageSize() throws {
        let row = MessageShotRenderer.Row(
            header: NSAttributedString(string: ""),
            body: NSAttributedString(string: "Message body", attributes: [.font: NSFont.systemFont(ofSize: 14)]),
            background: .red
        )
        let filledPNG = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: .white))
        let transparentPNG = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        let filled = try XCTUnwrap(NSBitmapImageRep(data: filledPNG))
        let transparent = try XCTUnwrap(NSBitmapImageRep(data: transparentPNG))

        XCTAssertEqual(transparent.pixelsWide, filled.pixelsWide)
        XCTAssertEqual(transparent.pixelsHigh, filled.pixelsHigh)
        let filledCanvas = try XCTUnwrap(filled.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(filledCanvas.alphaComponent, 1)
        XCTAssertEqual(try XCTUnwrap(transparent.colorAt(x: 0, y: 0)).alphaComponent, 0)

        let x = filled.pixelsWide / 2
        let y = filled.pixelsHigh / 2
        let filledCard = try XCTUnwrap(filled.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let transparentCard = try XCTUnwrap(transparent.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        XCTAssertNotEqual(filledCard, filledCanvas)
        XCTAssertEqual(transparentCard, filledCard)
        XCTAssertEqual(transparentCard.alphaComponent, 1)
    }

    func testThemePreferenceKeepsCurrentForMissingOrUnknownValues() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        XCTAssertEqual(options.theme, .current)
        XCTAssertFalse(options.showsReactions)
        options.theme = .nightAccent
        options.showsReactions = true
        options.showsBackground = false
        options.save(to: defaults)

        let reader = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var saved = MessageShotOptions(defaults: reader)
        XCTAssertEqual(saved.theme, .nightAccent)
        XCTAssertTrue(saved.showsReactions)
        XCTAssertFalse(saved.showsBackground)
        XCTAssertTrue(saved.showsTimestamps)

        defaults.set("future-theme", forKey: "gergram.messageShot.theme")
        saved = MessageShotOptions(defaults: reader)
        XCTAssertEqual(saved.theme, .current)
        XCTAssertTrue(saved.showsReactions)
        XCTAssertFalse(saved.showsBackground)
    }

    func testNativeThemeChoicesResolveIndependentlyOfTheCurrentPalette() {
        let custom = dayClassicPalette.withUpdatedName("Custom chat palette")
        XCTAssertTrue(MessageShotOptions.Theme.current.palette(current: custom) === custom)
        XCTAssertTrue(MessageShotOptions.Theme.dayClassic.palette(current: custom) === dayClassicPalette)
        XCTAssertTrue(MessageShotOptions.Theme.day.palette(current: custom) === whitePalette)
        XCTAssertTrue(MessageShotOptions.Theme.dark.palette(current: custom) === darkPalette)
        XCTAssertTrue(MessageShotOptions.Theme.nightAccent.palette(current: custom) === nightAccentPalette)
        XCTAssertEqual(MessageShotOptions.Theme.allCases.count, 5)
    }

    func testSelectedPalettesProduceDifferentCanvasAndCardPixels() throws {
        func render(_ choice: MessageShotOptions.Theme) throws -> NSBitmapImageRep {
            let palette = choice.palette(current: whitePalette)
            let row = MessageShotRenderer.Row(header: text(""), body: text("Message"), background: palette.bubbleBackground_incoming)
            let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: palette.background))
            return try XCTUnwrap(NSBitmapImageRep(data: png))
        }

        let light = try render(.current)
        let dark = try render(.dark)
        XCTAssertEqual(light.pixelsWide, dark.pixelsWide)
        XCTAssertEqual(light.pixelsHigh, dark.pixelsHigh)
        let lightCanvas = try XCTUnwrap(light.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let darkCanvas = try XCTUnwrap(dark.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let lightCard = try XCTUnwrap(light.colorAt(x: 300, y: 54)?.usingColorSpace(.deviceRGB))
        let darkCard = try XCTUnwrap(dark.colorAt(x: 300, y: 54)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(lightCanvas.redComponent, darkCanvas.redComponent)
        XCTAssertGreaterThan(lightCard.redComponent, darkCard.redComponent)
        XCTAssertNotEqual(lightCanvas, lightCard)
        XCTAssertNotEqual(darkCanvas, darkCard)
    }

    func testReactionSummaryIsOptInAndBoundsVisibleCounts() throws {
        let suiteName = "MessageShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var options = MessageShotOptions(defaults: defaults)
        let invalid = [(label: "", count: 4), (label: "❤️", count: 0), (label: String(repeating: "a", count: 65), count: 9)]
        let reactions = invalid + [(label: "👍", count: 42), (label: "⭐", count: 3)]
        XCTAssertEqual(options.reactionSummary(reactions), "")
        options.showsReactions = true
        XCTAssertEqual(options.reactionSummary(reactions), "👍 42   ⭐ 3")
        XCTAssertEqual(options.reactionSummary(invalid), "")
        let many = (1...17).map { (label: "👍", count: $0) }
        let parts = options.reactionSummary(many).components(separatedBy: "   ")
        XCTAssertEqual(parts, (1...16).map { "👍 \($0)" } + ["…"])
    }

    func testReactionFooterAddsItsOwnSpaceAndEmptyFooterDoesNot() throws {
        let footer = text("👍 42   ⭐ 3")
        let body = text("Caption")
        let attachment = MessageShotRenderer.Attachment(label: text("[Photo]"), thumbnail: try testImage(width: 40, height: 80))
        func render(_ footer: NSAttributedString?) throws -> NSBitmapImageRep {
            let row = MessageShotRenderer.Row(header: text("Author"), body: body, background: .white, attachments: [attachment], footer: footer)
            let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
            return try XCTUnwrap(NSBitmapImageRep(data: png))
        }
        let none = try render(nil)
        let empty = try render(text(""))
        let withFooter = try render(footer)
        let footerHeight = ceil(footer.boundingRect(
            with: NSSize(width: 504, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)

        XCTAssertEqual(none.pixelsWide, withFooter.pixelsWide)
        XCTAssertEqual(none.pixelsHigh, empty.pixelsHigh)
        XCTAssertEqual(withFooter.pixelsHigh - none.pixelsHigh, Int((footerHeight + 4) * 2))
    }

    func testOversizedFooterCountsTowardExportTextBudget() {
        let row = MessageShotRenderer.Row(
            header: text(""), body: text("A message"), background: .white,
            footer: text(String(repeating: "a", count: 16_000))
        )
        XCTAssertNil(MessageShotRenderer.png(rows: [row], background: nil))
    }

    func testEmptyHeaderUsesNoVerticalSpace() throws {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        let body = NSAttributedString(string: "Message body", attributes: attributes)
        let header = NSAttributedString(string: "Author • Timestamp", attributes: attributes)
        let emptyHeader = NSAttributedString(string: "", attributes: attributes)

        func render(_ header: NSAttributedString) throws -> NSBitmapImageRep {
            let row = MessageShotRenderer.Row(header: header, body: body, background: .white)
            let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: .white))
            return try XCTUnwrap(NSBitmapImageRep(data: png))
        }

        let imageWithHeader = try render(header)
        let imageWithoutHeader = try render(emptyHeader)
        let headerHeight = ceil(header.boundingRect(
            with: NSSize(width: 504, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)

        XCTAssertEqual(imageWithoutHeader.pixelsWide, imageWithHeader.pixelsWide)
        XCTAssertEqual(imageWithHeader.pixelsHigh - imageWithoutHeader.pixelsHigh, Int((headerHeight + 4) * 2))
    }

    func testMissingThumbnailKeepsAttachmentLabel() throws {
        let body = text("A caption")
        let label = text("[Photo]")
        let attachment = MessageShotRenderer.Attachment(label: label, thumbnail: nil)
        let row = MessageShotRenderer.Row(header: text(""), body: body, background: .white, attachments: [attachment])
        let original = MessageShotRenderer.Row(header: text(""), body: text("A caption\n[Photo]"), background: .white)

        XCTAssertEqual(
            try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil)),
            try XCTUnwrap(MessageShotRenderer.png(rows: [original], background: nil))
        )
    }

    func testThumbnailIsDrawnWithOriginalOrientation() throws {
        let thumbnail = try testImage(width: 40, height: 80)
        let row = MessageShotRenderer.Row(
            header: text(""), body: text(""), background: .white,
            attachments: [.init(label: text("[Photo]"), thumbnail: thumbnail)]
        )
        let png = try XCTUnwrap(MessageShotRenderer.png(rows: [row], background: nil))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        let top = try XCTUnwrap(image.colorAt(x: 65, y: 66)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(image.colorAt(x: 65, y: 120)?.usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(top.redComponent, top.blueComponent)
        XCTAssertGreaterThan(bottom.blueComponent, bottom.redComponent)
        XCTAssertEqual(try XCTUnwrap(image.colorAt(x: 0, y: 0)).alphaComponent, 0)
    }

    func testOversizedPreviewLayoutFallsBackToPlaceholders() throws {
        let thumbnail = try testImage(width: 400, height: 400)
        let label = text("[Photo]")
        let preview = MessageShotRenderer.Row(
            header: text(""), body: text(""), background: .white,
            attachments: [.init(label: label, thumbnail: thumbnail)]
        )
        let placeholder = MessageShotRenderer.Row(header: text(""), body: label, background: .white)

        XCTAssertEqual(
            try XCTUnwrap(MessageShotRenderer.png(rows: Array(repeating: preview, count: 20), background: nil)),
            try XCTUnwrap(MessageShotRenderer.png(rows: Array(repeating: placeholder, count: 20), background: nil))
        )
    }

    func testCachedThumbnailDownsamplesAndRejectsCorruptData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = NSBitmapImageRep(cgImage: try testImage(width: 1600, height: 800))
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)

        let thumbnail = try XCTUnwrap(MessageShotRenderer.thumbnail(at: url.path))
        XCTAssertEqual(thumbnail.width, 640)
        XCTAssertEqual(thumbnail.height, 320)

        try Data([0, 1, 2, 3]).write(to: url)
        XCTAssertNil(MessageShotRenderer.thumbnail(at: url.path))
    }

    func testCachedThumbnailRejectsOversizedFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = NSBitmapImageRep(cgImage: try testImage(width: 4, height: 4))
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
        let file = try FileHandle(forWritingTo: url)
        file.truncateFile(atOffset: 8 * 1024 * 1024 + 1)
        file.closeFile()

        XCTAssertNil(MessageShotRenderer.thumbnail(at: url.path))
    }

    private func text(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14)])
    }

    private func testImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }
}
