import AppKit
import InAppSettings
import TelegramTheme
import TGUIKit
import XCTest

final class AvatarCornerAppearanceTests: XCTestCase {
    func testDefaultAndExplicitAvatarShapesArePreserved() {
        let size = CGSize(width: 48, height: 40)
        let standard = AvatarCornerAppearance()
        XCTAssertNil(standard.preferredRadius(for: size, isForum: false, explicitRadius: nil, preservesShape: false))
        XCTAssertNil(standard.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: false))

        let shared = AvatarCornerAppearance(radius: 0, usesSingleRadius: true)
        XCTAssertNil(shared.preferredRadius(for: size, isForum: true, explicitRadius: 6, preservesShape: false))
        XCTAssertNil(shared.preferredRadius(for: size, isForum: false, explicitRadius: nil, preservesShape: true))
        XCTAssertNil(shared.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: true))
    }

    func testForumAvatarsOnlyUseTheSharedRadiusWhenEnabled() {
        let size = CGSize(width: 46, height: 60)
        for radius in AvatarCornerPreferences.allowedRadii {
            let independent = AvatarCornerAppearance(radius: radius)
            let shared = AvatarCornerAppearance(radius: radius, usesSingleRadius: true)
            XCTAssertNil(independent.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: false))
            XCTAssertEqual(shared.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: false), CGFloat(radius))
            XCTAssertEqual(independent.preferredRadius(for: size, isForum: false, explicitRadius: nil, preservesShape: false),
                           radius == AvatarCornerPreferences.defaultRadius ? nil : CGFloat(radius))
        }
    }

    func testNativeBitmapClipUsesItsRenderScale() throws {
        let size = CGSize(width: 46, height: 46)
        let square = AvatarCornerAppearance(radius: 0, usesSingleRadius: true)
        let rounded = AvatarCornerAppearance(radius: 23, usesSingleRadius: true)
        let source = try XCTUnwrap(generateImage(size, contextGenerator: { size, context in
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }, scale: 1))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))

        for scale: CGFloat in [1, 2] {
            let squareRadius = try XCTUnwrap(square.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: false))
            let roundedRadius = try XCTUnwrap(rounded.preferredRadius(for: size, isForum: true, explicitRadius: nil, preservesShape: false))
            let squareBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(roundImage(data, size, cornerRadius: squareRadius, scale: scale, radiusUsesImageScale: true)))
            let roundedBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(roundImage(data, size, cornerRadius: roundedRadius, scale: scale, radiusUsesImageScale: true)))
            XCTAssertEqual(squareBitmap.pixelsWide, Int(size.width * scale))
            XCTAssertEqual(roundedBitmap.pixelsHigh, Int(size.height * scale))
            XCTAssertEqual(squareBitmap.colorAt(x: 0, y: 0)?.alphaComponent, 1)
            XCTAssertEqual(roundedBitmap.colorAt(x: Int(4 * scale), y: Int(4 * scale))?.alphaComponent, 0)
            XCTAssertEqual(roundedBitmap.colorAt(x: roundedBitmap.pixelsWide / 2, y: roundedBitmap.pixelsHigh / 2)?.alphaComponent, 1)
        }
    }

    func testPreferencePersistsBothOptionsAndDisposesObserver() throws {
        let suite = "Gergram.AvatarCornerAppearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AvatarCornerPreferences(defaults: defaults)
        var values: [AvatarCornerAppearance] = []
        let subscription = preferences.signal.start(next: { values.append($0) })
        preferences.setRadius(0)
        preferences.setRadius(0)
        preferences.setRadius(24)
        preferences.setUsesSingleRadius(true)
        subscription.dispose()
        preferences.setRadius(23)

        XCTAssertEqual(values, [.init(), .init(radius: 0), .init(radius: 0, usesSingleRadius: true)])
        XCTAssertEqual(AvatarCornerPreferences(defaults: defaults).appearance, .init(usesSingleRadius: true))
        defaults.set(-1, forKey: "Gergram.Appearance.AvatarRadius")
        XCTAssertEqual(AvatarCornerPreferences(defaults: defaults).appearance.radius, 23)
    }

    func testCacheKeysSeparateAccountsAndShapesEvenWithCollidingHashes() throws {
        struct Key: Hashable {
            let style: PeerAvatarCacheStyle
            func hash(into hasher: inout Hasher) { hasher.combine(0) }
        }
        let cache = ScopedImageCache(countLimit: 4, byteLimit: 4096, idleTimeout: 60, closedScopeGrace: 0)
        let image = try XCTUnwrap(generateImage(CGSize(width: 8, height: 8), contextGenerator: { size, context in
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }, scale: 1))
        let stored = Key(style: .init(accountId: 1, isForum: true, isMonoforum: false, preferredRadius: 0))
        cache.setImage(image, sampleBuffer: nil, forKey: stored.hashValue, identity: stored)

        XCTAssertTrue(cache.image(forKey: stored.hashValue, identity: stored)?.0 === image)
        XCTAssertNil(cache.image(forKey: stored.hashValue))
        let otherStyles = [
            PeerAvatarCacheStyle(accountId: 2, isForum: true, isMonoforum: false, preferredRadius: 0),
            PeerAvatarCacheStyle(accountId: 1, isForum: true, isMonoforum: false, preferredRadius: 8),
            PeerAvatarCacheStyle(accountId: 1, isForum: true, isMonoforum: true, preferredRadius: 0),
            PeerAvatarCacheStyle(accountId: 1, isForum: true, isMonoforum: false, forceForum: true, preferredRadius: 0)
        ]
        for style in otherStyles {
            let other = Key(style: style)
            XCTAssertEqual(other.hashValue, stored.hashValue)
            XCTAssertNil(cache.image(forKey: other.hashValue, identity: other))
        }
    }
}
