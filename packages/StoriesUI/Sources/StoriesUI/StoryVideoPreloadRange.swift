enum StoryVideoPreloadRange {
    private static let fallbackBytes: Int64 = 512 * 1024

    static func prefix(advertisedBytes: Int64?, fileSize: Int64?, allowFallback: Bool = false) -> Range<Int64>? {
        let requestedBytes: Int64
        if let advertisedBytes, advertisedBytes > 0 {
            requestedBytes = advertisedBytes
        } else if allowFallback {
            requestedBytes = fallbackBytes
        } else {
            return nil
        }
        let length = min(requestedBytes, fileSize ?? requestedBytes)
        return length > 0 ? 0 ..< length : nil
    }
}
