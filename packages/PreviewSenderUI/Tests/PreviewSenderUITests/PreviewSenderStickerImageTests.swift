import CoreGraphics
import Darwin
import Foundation
import ImageIO
import XCTest
@testable import PreviewSenderUI

final class PreviewSenderStickerImageTests: XCTestCase {
    func testPNGBecomesTransparentWebPAndOriginalIsUnchanged() throws {
        let png = try makeImage(width: 700, height: 350, type: "public.png")
        let url = try write(png, extension: "png")

        XCTAssertTrue(PreviewSenderStickerImage.isCandidate(url))
        let result = try XCTUnwrap(PreviewSenderStickerImage.prepare(url))
        XCTAssertEqual(result.width, 512)
        XCTAssertEqual(result.height, 257)
        XCTAssertEqual(try Data(contentsOf: url), png)
        try assertStaticSticker(result)
    }

    func testSmallJPEGIsScaledAndOrientationIsApplied() throws {
        let jpeg = try makeImage(width: 96, height: 48, type: "public.jpeg", orientation: 6)
        let url = try write(jpeg, extension: "JPEG")
        let result = try XCTUnwrap(PreviewSenderStickerImage.prepare(url))
        XCTAssertEqual(result.width, 257)
        XCTAssertEqual(result.height, 512)
        try assertStaticSticker(result)
    }

    func testRejectsSpoofedAndMalformedInputs() throws {
        let png = try makeImage(width: 96, height: 48, type: "public.png")
        let urls = try [
            write(png, extension: "jpeg"),
            write(png, extension: "gif"),
            write(Data(png.prefix(20)), extension: "png"),
            write(Data("not an image".utf8), extension: "png")
        ]
        for url in urls {
            XCTAssertFalse(PreviewSenderStickerImage.isCandidate(url))
            XCTAssertNil(PreviewSenderStickerImage.prepare(url))
        }
    }

    func testRejectsOverBudgetFileAndDoesNotReadTheTargetOfASymlink() throws {
        let png = try makeImage(width: 96, height: 48, type: "public.png")
        let original = try write(png, extension: "png")
        let link = original.deletingLastPathComponent().appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertFalse(PreviewSenderStickerImage.isCandidate(link))
        XCTAssertNil(PreviewSenderStickerImage.prepare(link))
        let pipe = original.deletingLastPathComponent().appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertFalse(PreviewSenderStickerImage.isCandidate(pipe))
        XCTAssertNil(PreviewSenderStickerImage.prepare(pipe))

        let large = try write(png, extension: "png")
        let handle = try FileHandle(forWritingTo: large)
        handle.truncateFile(atOffset: 32 * 1024 * 1024 + 1)
        handle.closeFile()
        XCTAssertFalse(PreviewSenderStickerImage.isCandidate(large))
        XCTAssertNil(PreviewSenderStickerImage.prepare(large))
        XCTAssertEqual(try Data(contentsOf: original), png)
    }

    func testStickerModeInvalidatesAnEarlierFilePreview() {
        let url = URL(fileURLWithPath: "/image.png")
        let fileOrder = PreviewSenderAttachmentOrder(urls: [url], layout: .items)
        let stickerOrder = fileOrder.updating(urls: [url], layout: .sticker)
        let fallbackOrder = stickerOrder.updating(urls: [url], layout: .items)

        XCTAssertEqual(stickerOrder.rowCount, 1)
        XCTAssertEqual(stickerOrder.range(forRow: 0), 0..<1)
        XCTAssertNotEqual(fileOrder, stickerOrder)
        XCTAssertNotEqual(fallbackOrder, stickerOrder)
        XCTAssertNotEqual(fallbackOrder, fileOrder)
    }

    private func assertStaticSticker(_ result: PreviewSenderStickerImage, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertLessThan(result.data.count, 300 * 1024, file: file, line: line)
        XCTAssertEqual(String(data: result.data.prefix(4), encoding: .ascii), "RIFF", file: file, line: line)
        XCTAssertEqual(String(data: result.data.dropFirst(8).prefix(4), encoding: .ascii), "WEBP", file: file, line: line)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil), file: file, line: line)
        XCTAssertEqual(CGImageSourceGetCount(source), 1, file: file, line: line)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), file: file, line: line)
        XCTAssertEqual(image.width, Int(result.width), file: file, line: line)
        XCTAssertEqual(image.height, Int(result.height), file: file, line: line)

        let bitmap = try XCTUnwrap(makeBitmap(width: image.width, height: image.height), file: file, line: line)
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(bitmap.data, file: file, line: line).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(pixels[3], 0, file: file, line: line)
        XCTAssertEqual(pixels[bitmap.bytesPerRow * (image.height / 2) + image.width / 2 * 4 + 3], 255, file: file, line: line)
    }

    private func makeBitmap(width: Int, height: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func makeImage(width: Int, height: Int, type: String, orientation: Int = 1) throws -> Data {
        let bitmap = try XCTUnwrap(makeBitmap(width: width, height: height))
        bitmap.setFillColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(bitmap.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func write(_ data: Data, extension ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("image").appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }
}
