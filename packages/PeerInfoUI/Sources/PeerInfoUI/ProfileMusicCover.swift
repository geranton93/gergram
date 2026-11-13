import AppKit
import Darwin
import ImageIO

struct ProfileMusicCover {
    static let maximumBytes = 2 * 1024 * 1024
    private static let maximumSide = 4_096
    private static let maximumPixels = 8_000_000
    private static let sampleSide = 16
    private static let supportedTypes: Set<String> = ["public.jpeg", "public.png", "org.webmproject.webp", "public.webp"]

    let image: CGImage
    let background: NSColor
    let primary: NSColor
    let secondary: NSColor

    static func load(path: String, accountId: Int64, resourceId: String, pixelSize: Int, isDark: Bool) -> Self? {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              (1...Int64(maximumBytes)).contains(info.st_size) else { return nil }

        let pixelSize = min(96, max(16, pixelSize))
        let stamp = info.st_mtimespec
        let key = "\(accountId):\(info.st_dev):\(info.st_ino):\(info.st_size):\(stamp.tv_sec):\(stamp.tv_nsec):\(pixelSize):\(isDark):\(resourceId)" as NSString
        if let entry = cache.object(forKey: key) {
            return entry.cover
        }

        var bytes = Data(count: Int(info.st_size))
        let finished = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += count
                } else if count == 0 || errno != EINTR {
                    return false
                }
            }
            return true
        }
        var after = stat()
        guard finished, fstat(descriptor, &after) == 0, after.st_size == info.st_size,
              after.st_mtimespec.tv_sec == stamp.tv_sec, after.st_mtimespec.tv_nsec == stamp.tv_nsec else { return nil }
        guard let cover = decode(bytes, pixelSize: pixelSize, isDark: isDark) else { return nil }
        cache.setObject(Entry(cover: cover), forKey: key, cost: cover.image.bytesPerRow * cover.image.height)
        return cover
    }

    private static func decode(_ bytes: Data, pixelSize: Int, isDark: Bool) -> Self? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?, supportedTypes.contains(type),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...maximumSide).contains(width), (1...maximumSide).contains(height), width * height <= maximumPixels,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let color = sample(image) else { return nil }

        let shade = isDark ? 0.62 : 0.76
        var background = color.scaled(shade)
        let primary = RGB(red: 1, green: 1, blue: 1)
        let secondary = RGB(red: 0.85, green: 0.85, blue: 0.85)
        let maximumBackgroundLuminance = (secondary.luminance + 0.05) / 4.5 - 0.05
        while background.luminance > maximumBackgroundLuminance {
            background = background.scaled(0.9)
        }
        return Self(image: image, background: background.color, primary: primary.color, secondary: secondary.color)
    }

    private static func sample(_ image: CGImage) -> RGB? {
        let side = sampleSide
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        context.clear(bounds)
        context.draw(image, in: bounds)
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var weight = 0.0
        for offset in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[offset + 3])
            guard alpha >= 64 else { continue }
            let r = min(1, Double(pixels[offset]) / alpha)
            let g = min(1, Double(pixels[offset + 1]) / alpha)
            let b = min(1, Double(pixels[offset + 2]) / alpha)
            let saturation = max(r, g, b) - min(r, g, b)
            let prominence = alpha * (1 + saturation * 2)
            red += r * prominence
            green += g * prominence
            blue += b * prominence
            weight += prominence
        }
        guard weight > 0 else { return nil }
        return RGB(red: red / weight, green: green / weight, blue: blue / weight)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var color: NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }

        var luminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func scaled(_ factor: Double) -> Self {
            Self(red: red * factor, green: green * factor, blue: blue * factor)
        }
    }

    private final class Entry {
        let cover: ProfileMusicCover

        init(cover: ProfileMusicCover) {
            self.cover = cover
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 48
        cache.totalCostLimit = 1 * 1024 * 1024
        return cache
    }()
}
