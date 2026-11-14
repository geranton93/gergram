import CoreGraphics
import Darwin
import Foundation
import ImageIO
import TextRecognizing

struct PreviewSenderStickerImage {
    private static let maxSourceBytes = 32 * 1024 * 1024
    private static let maxSourcePixels = 32_000_000
    private static let maxSourceSide = 12_000
    private static let stickerSide = 512
    private static let maxStickerBytes = 300 * 1024 - 1
    private static let imageTypes = [
        "png": "public.png",
        "jpg": "public.jpeg",
        "jpeg": "public.jpeg",
        "jpe": "public.jpeg",
        "jfif": "public.jpeg"
    ]

    let data: Data
    let width: Int32
    let height: Int32

    static func isCandidate(_ url: URL) -> Bool {
        guard let type = imageTypes[url.pathExtension.lowercased()] else { return false }
        let signature: [UInt8] = type == "public.png" ? [137, 80, 78, 71, 13, 10, 26, 10] : [255, 216, 255]
        return withSourceFile(url) { descriptor, size in
            guard size >= 32, let header = read(descriptor, count: signature.count) else { return false }
            return header.elementsEqual(signature)
        } ?? false
    }

    static func prepare(_ url: URL) -> Self? {
        let inset = 1
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: stickerSide - inset * 2,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let source = source(for: url),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.width > 0, image.height > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let scale = CGFloat(stickerSide - inset * 2) / CGFloat(max(image.width, image.height))
        let contentWidth = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let contentHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let width = contentWidth + inset * 2
        let height = contentHeight + inset * 2
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        canvas.clear(CGRect(x: 0, y: 0, width: width, height: height))
        canvas.interpolationQuality = .high
        canvas.draw(image, in: CGRect(x: inset, y: inset, width: contentWidth, height: contentHeight))

        guard let transparentImage = canvas.makeImage(),
              let (data, size) = stickerWebP(from: transparentImage),
              !data.isEmpty, data.count <= maxStickerBytes else {
            return nil
        }
        return Self(data: data, width: Int32(size.width), height: Int32(size.height))
    }

    private static func source(for url: URL) -> CGImageSource? {
        guard let type = imageTypes[url.pathExtension.lowercased()],
              let bytes = withSourceFile(url, read),
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == type,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...8).contains((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1),
              (1...maxSourceSide).contains(width), (1...maxSourceSide).contains(height),
              width * height <= maxSourcePixels else {
            return nil
        }
        return source
    }

    private static func withSourceFile<Value>(_ url: URL, _ read: (Int32, Int) -> Value?) -> Value? {
        guard url.isFileURL else { return nil }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              (1...Int64(maxSourceBytes)).contains(info.st_size) else { return nil }
        return read(descriptor, Int(info.st_size))
    }

    private static func read(_ descriptor: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < count {
                let result = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if result > 0 {
                    offset += result
                } else if result == 0 || errno != EINTR {
                    return false
                }
            }
            return true
        }
        return complete ? data : nil
    }
}
