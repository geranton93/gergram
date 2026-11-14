import AppKit
import ImageIO
import InAppSettings
import SwiftSignalKit
import XCTest
@testable import PeerInfoUI

final class ProfileMusicCoverTests: XCTestCase {
    private func inTemporaryDirectory(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    private func makeArtwork(at url: URL, color: NSColor, width: Int = 120, height: Int = 70) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func cover(_ url: URL, account: Int64 = 1, resource: String = "cover", pixels: Int = 32, dark: Bool = false) -> ProfileMusicCover? {
        ProfileMusicCover.load(path: url.path, accountId: account, resourceId: resource, pixelSize: pixels, isDark: dark)
    }

    private func luminance(_ color: NSColor) throws -> CGFloat {
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { component in
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    func testAdaptsToArtworkAndKeepsBothLabelsReadable() throws {
        try inTemporaryDirectory { directory in
            let colors: [NSColor] = [.white, .black, .systemYellow, .systemPurple, .systemBlue]
            for (index, color) in colors.enumerated() {
                let file = directory.appendingPathComponent("artwork-\(index)")
                try makeArtwork(at: file, color: color)
                for dark in [false, true] {
                    let artwork = try XCTUnwrap(cover(file, dark: dark))
                    XCTAssertEqual(artwork.background.alphaComponent, 1)
                    for text in [artwork.primary, artwork.secondary] {
                        XCTAssertGreaterThanOrEqual((try luminance(text) + 0.05) / (try luminance(artwork.background) + 0.05), 4.5)
                    }
                }
            }
            let yellow = try XCTUnwrap(cover(directory.appendingPathComponent("artwork-2")))
            let blue = try XCTUnwrap(cover(directory.appendingPathComponent("artwork-4")))
            XCTAssertGreaterThan(yellow.background.redComponent, yellow.background.blueComponent)
            XCTAssertGreaterThan(blue.background.blueComponent, blue.background.redComponent)
        }
    }

    func testCacheSeparatesAccountResourceThemeAndBackingSize() throws {
        try inTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("cover")
            try makeArtwork(at: file, color: NSColor(srgbRed: 0.38, green: 0.24, blue: 0.58, alpha: 1))
            let original = try XCTUnwrap(cover(file))
            let repeated = try XCTUnwrap(cover(file))
            XCTAssertTrue(original.image === repeated.image)

            let otherAccount = try XCTUnwrap(cover(file, account: 2))
            let otherResource = try XCTUnwrap(cover(file, resource: "other cover"))
            let dark = try XCTUnwrap(cover(file, dark: true))
            let highDensity = try XCTUnwrap(cover(file, pixels: 64))
            XCTAssertFalse(original.image === otherAccount.image)
            XCTAssertFalse(original.image === otherResource.image)
            XCTAssertLessThan(try luminance(dark.background), try luminance(original.background))
            XCTAssertEqual(max(original.image.width, original.image.height), 32)
            XCTAssertEqual(max(highDensity.image.width, highDensity.image.height), 64)
        }
    }

    func testReplacementInvalidatesTheCache() throws {
        try inTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("cover")
            try makeArtwork(at: file, color: .red)
            let original = try XCTUnwrap(cover(file))
            XCTAssertGreaterThan(original.background.redComponent, original.background.blueComponent)

            let replacement = directory.appendingPathComponent("replacement")
            try makeArtwork(at: replacement, color: .blue)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: replacement, to: file)
            let updated = try XCTUnwrap(cover(file))
            XCTAssertGreaterThan(updated.background.blueComponent, updated.background.redComponent)
        }
    }

    func testPendingFirstCoverUsesLaterCachedArtworkAndCanUpgrade() throws {
        try inTemporaryDirectory { directory in
            let earlierFile = directory.appendingPathComponent("earlier")
            let laterFile = directory.appendingPathComponent("later")
            try makeArtwork(at: earlierFile, color: .red)
            try makeArtwork(at: laterFile, color: .blue)
            let earlier = Promise<String>()
            let queue = Queue(name: "ProfileMusicCoverTests")
            let available = expectation(description: "Later cached candidate was displayed")
            let preferred = expectation(description: "Earlier candidate was displayed after arriving")
            let signal = ProfileMusicCover.observeCached([
                .init(resourceId: "earlier", cachedPath: earlier.get()),
                .init(resourceId: "later", cachedPath: .single(laterFile.path)),
            ], accountId: 1, pixelSize: 32, isDark: false, on: queue)
            let observation = signal.start(next: { artwork in
                guard let artwork else { return }
                if artwork.background.blueComponent > artwork.background.redComponent {
                    available.fulfill()
                } else {
                    preferred.fulfill()
                }
            })
            defer { observation.dispose() }

            wait(for: [available], timeout: 3)
            earlier.set(.single(earlierFile.path))
            wait(for: [preferred], timeout: 3)
        }
    }

    func testInvalidFirstCoverUsesLaterCandidateAndCapsObservers() throws {
        try inTemporaryDirectory { directory in
            let corrupt = directory.appendingPathComponent("invalid")
            try Data([0]).write(to: corrupt)
            let valid = directory.appendingPathComponent("valid")
            try makeArtwork(at: valid, color: .blue)
            let queue = Queue(name: "ProfileMusicCoverTests")
            let available = expectation(description: "Later valid candidate was displayed")
            let unexpected = Signal<String, NoError> { _ in
                XCTFail("A fifth candidate was observed")
                return EmptyDisposable
            }
            let signal = ProfileMusicCover.observeCached([
                .init(resourceId: "invalid", cachedPath: .single(corrupt.path)),
                .init(resourceId: "valid", cachedPath: .single(valid.path)),
                .init(resourceId: "pending-one", cachedPath: .never()),
                .init(resourceId: "pending-two", cachedPath: .never()),
                .init(resourceId: "ignored", cachedPath: unexpected),
            ], accountId: 1, pixelSize: 32, isDark: false, on: queue)
            let observation = signal.start(next: { artwork in
                guard let artwork else { return }
                XCTAssertGreaterThan(artwork.background.blueComponent, artwork.background.redComponent)
                available.fulfill()
            })
            defer { observation.dispose() }
            wait(for: [available], timeout: 3)
        }
    }

    func testMissingTransparentCorruptAndOversizedArtUsesFallback() throws {
        try inTemporaryDirectory { directory in
            let missing = directory.appendingPathComponent("missing")
            XCTAssertNil(cover(missing))
            XCTAssertNil(cover(directory))

            let invalid = directory.appendingPathComponent("invalid")
            try Data("unreadable artwork".utf8).write(to: invalid)
            XCTAssertNil(cover(invalid))

            let transparent = directory.appendingPathComponent("transparent")
            try makeArtwork(at: transparent, color: .clear)
            XCTAssertNil(cover(transparent))

            let valid = directory.appendingPathComponent("valid")
            try makeArtwork(at: valid, color: .red)
            let linked = directory.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: valid)
            XCTAssertNil(cover(linked))

            let wide = directory.appendingPathComponent("wide")
            try makeArtwork(at: wide, color: .red, width: 4_097, height: 1)
            XCTAssertNil(cover(wide))

            let large = directory.appendingPathComponent("large")
            try Data(count: ProfileMusicCover.maximumBytes + 1).write(to: large)
            XCTAssertNil(cover(large))
        }
    }

    func testPreferenceIsEnabledByDefaultAndPublishesChanges() throws {
        let suite = "Gergram.ProfileMusicCover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = ProfileMusicCoverPreferences(defaults: defaults)
        XCTAssertTrue(preference.isAdaptive)
        var observed: [Bool] = []
        let observation = preference.signal.start(next: { observed.append($0) })
        preference.setAdaptive(false)
        preference.setAdaptive(false)
        XCTAssertFalse(ProfileMusicCoverPreferences(defaults: defaults).isAdaptive)
        preference.setAdaptive(true)
        observation.dispose()
        preference.setAdaptive(false)
        XCTAssertEqual(observed, [true, false, true])
    }
}
