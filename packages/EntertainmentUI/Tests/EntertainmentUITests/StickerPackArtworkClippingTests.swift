import AppKit
@testable import EntertainmentUI
import XCTest

final class StickerPackArtworkClippingTests: XCTestCase {
    private let tileSize = CGSize(width: 60, height: 60)

    private func makeArtwork(scale: CGFloat = 1) -> CALayer {
        let artwork = CALayer()
        artwork.frame = CGRect(origin: .zero, size: tileSize)
        artwork.contentsScale = scale
        artwork.contentsGravity = .center
        artwork.isOpaque = true
        return artwork
    }

    private func makeFrame(size: CGSize, color: NSColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.clear(CGRect(x: size.width / 2 - 2, y: size.height / 2 - 2, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }

    private func rasterize(_ layer: CALayer) throws -> NSBitmapImageRep {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(tileSize.width),
            height: Int(tileSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        layer.render(in: context)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
    }

    func testClipsTheFittedArtworkAndKeepsItsAlphaAcrossFrames() throws {
        let size = CGSize(width: 60, height: 28)
        let artwork = makeArtwork()
        let tile = StickerPackArtworkClipping.tile(for: artwork, fittedSize: size)
        XCTAssertEqual(tile.bounds.size, tileSize)
        XCTAssertEqual(artwork.bounds.size, tileSize)
        XCTAssertFalse(artwork.isOpaque)

        for color in [NSColor.red, .blue] {
            let frame = try makeFrame(size: size, color: color)
            artwork.contents = frame
            let image = try rasterize(tile)
            XCTAssertEqual(image.colorAt(x: 0, y: 16)?.alphaComponent, 0)
            XCTAssertEqual(image.colorAt(x: 30, y: 5)?.alphaComponent, 0)
            XCTAssertEqual(image.colorAt(x: 30, y: 30)?.alphaComponent, 0)
            let visible = try XCTUnwrap(image.colorAt(x: 10, y: 30)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(visible.alphaComponent, 1)
            XCTAssertEqual(visible.redComponent, color.redComponent, accuracy: 0.01)
            XCTAssertEqual(visible.blueComponent, color.blueComponent, accuracy: 0.01)
            XCTAssertTrue(artwork.contents as AnyObject? === frame)
        }
    }

    func testClippingLeavesEditingOverlaysOutsideTheArtworkMask() throws {
        let artwork = makeArtwork()
        let tile = StickerPackArtworkClipping.tile(for: artwork, fittedSize: CGSize(width: 60, height: 24))
        let badge = CALayer()
        badge.frame = CGRect(x: 3, y: 3, width: 20, height: 20)
        badge.backgroundColor = NSColor.green.cgColor
        tile.addSublayer(badge)

        let image = try rasterize(tile)
        XCTAssertEqual(image.colorAt(x: 5, y: 54)?.alphaComponent, 1)
        XCTAssertTrue(badge.superlayer === tile)
        XCTAssertNil(tile.mask)
    }

    func testMaskMatchesPixelAlignedBoundsAndClampsSmallCorners() throws {
        let artwork = makeArtwork(scale: 2)
        let tile = StickerPackArtworkClipping.tile(for: artwork, fittedSize: CGSize(width: 3, height: 60))
        let mask = try XCTUnwrap(artwork.mask as? CAShapeLayer)
        let path = try XCTUnwrap(mask.path)

        XCTAssertEqual(path.boundingBox, CGRect(x: 28.5, y: 0, width: 3, height: 60))
        XCTAssertFalse(path.contains(CGPoint(x: 28.55, y: 0.05)))
        XCTAssertTrue(path.contains(CGPoint(x: 30, y: 1)))
        XCTAssertEqual(mask.contentsScale, 2)
        XCTAssertTrue(artwork.superlayer === tile)
    }

    func testExcludedArtworkRemainsUnmasked() throws {
        let artwork = makeArtwork()
        let tile = StickerPackArtworkClipping.tile(for: artwork, fittedSize: nil)
        let frame = try makeFrame(size: tileSize, color: .red)
        artwork.contents = frame

        let image = try rasterize(tile)
        XCTAssertEqual(image.colorAt(x: 0, y: 0)?.alphaComponent, 1)
        XCTAssertNil(artwork.mask)
    }
}
