import Foundation

public struct SpotifyDesktopLink {
    public let appURL: URL
    public let webURL: URL

    public init?(url: String) {
        let https = "https://"
        guard url.prefix(https.count).lowercased() == https else { return nil }

        let authority = url.dropFirst(https.count).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard authority.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        let host = authority.lowercased()
        guard host == "open.spotify.com" || host == "open.spotify.com:443",
              let components = URLComponents(string: url), components.fragment == nil,
              let webURL = components.url else { return nil }

        let queryItems = components.queryItems ?? []
        guard queryItems.allSatisfy({ $0.name == "si" || $0.name.hasPrefix("utm_") }) else { return nil }

        var path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if path.last == "" {
            path.removeLast()
        }

        let segments = Array(path)
        let type = segments.first?.lowercased()
        let uri: String
        switch (type, segments.count) {
        case ("track", 2), ("album", 2), ("artist", 2), ("playlist", 2):
            guard let type, Self.isIdentifier(segments[1]) else { return nil }
            uri = "spotify:\(type):\(segments[1])"
        case ("user", 2):
            guard Self.isIdentifier(segments[1], isUsername: true) else { return nil }
            uri = "spotify:user:\(segments[1])"
        case ("user", 4) where segments[2].lowercased() == "playlist":
            guard Self.isIdentifier(segments[1], isUsername: true), Self.isIdentifier(segments[3]) else { return nil }
            uri = "spotify:user:\(segments[1]):playlist:\(segments[3])"
        default:
            return nil
        }

        guard let appURL = URL(string: uri) else { return nil }
        self.appURL = appURL
        self.webURL = webURL
    }

    private static func isIdentifier(_ value: Substring, isUsername: Bool = false) -> Bool {
        guard (1...128).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                || (isUsername && (byte == 45 || byte == 95))
        }
    }
}
