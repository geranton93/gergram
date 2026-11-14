import Foundation

enum SocialPostPreview {
    static func hasUsableMediaSize(_ size: CGSize?) -> Bool {
        guard let size else { return false }
        return size.width.isFinite && size.height.isFinite && size.width >= 200 && size.height > 0
    }

    static func prefersLargeMedia(for url: String) -> Bool {
        guard url.utf8.count <= 4096,
              url.utf8.allSatisfy({ $0 > 32 && $0 != 127 }),
              url.prefix(8).lowercased() == "https://" else {
            return false
        }

        let authority = url.dropFirst(8).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty, authority.utf8.allSatisfy({ $0 < 128 }),
              let components = URLComponents(string: url),
              let host = components.host?.lowercased(),
              authority.lowercased() == host || authority.lowercased() == "\(host):443",
              components.percentEncodedPath.hasPrefix("/") else {
            return false
        }

        var segments = components.percentEncodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if segments.last == "" {
            segments.removeLast()
        }
        guard segments.allSatisfy({ !$0.isEmpty }) else {
            return false
        }

        switch (host, segments.count) {
        case ("x.com", 3), ("www.x.com", 3), ("twitter.com", 3), ("www.twitter.com", 3), ("mobile.twitter.com", 3):
            return isSlug(segments[0]) && segments[1] == "status" && isNumericID(segments[2])
        case ("x.com", 4), ("www.x.com", 4), ("twitter.com", 4), ("www.twitter.com", 4), ("mobile.twitter.com", 4):
            return segments[0] == "i" && segments[1] == "web" && segments[2] == "status" && isNumericID(segments[3])
        case ("tiktok.com", 3), ("www.tiktok.com", 3), ("m.tiktok.com", 3):
            return segments[0].first == "@" && isSlug(segments[0].dropFirst(), allowsDot: true)
                && (segments[1] == "video" || segments[1] == "photo") && isNumericID(segments[2])
        case ("reddit.com", 4...5), ("www.reddit.com", 4...5):
            return segments[0] == "r" && isSlug(segments[1]) && segments[2] == "comments"
                && isSlug(segments[3]) && (segments.count == 4 || isSlug(segments[4]))
        case ("instagram.com", 2), ("www.instagram.com", 2):
            return ["p", "reel", "tv"].contains(segments[0]) && isSlug(segments[1])
        case ("pixiv.net", 2), ("www.pixiv.net", 2):
            return segments[0] == "artworks" && isNumericID(segments[1])
        case ("pixiv.net", 3), ("www.pixiv.net", 3):
            return ["en", "ja", "ko", "zh", "zh-cn", "zh-tw"].contains(segments[0])
                && segments[1] == "artworks" && isNumericID(segments[2])
        default:
            return false
        }
    }

    private static func isNumericID(_ value: Substring) -> Bool {
        (1...32).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isSlug(_ value: Substring, allowsDot: Bool = false) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 95 || (allowsDot && $0 == 46)
        }
    }
}
