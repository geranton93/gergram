enum DirectMediaReadAhead {
    private static let probeBytes: Int64 = 512 * 1024
    private static let windowBytes: Int64 = 2 * 1024 * 1024

    static func boundedRange(at offset: Int64, length: Int64, fileSize: Int64) -> Range<Int64>? {
        guard offset >= 0, offset < fileSize, length > 0 else {
            return nil
        }
        return offset ..< (offset + min(length, fileSize - offset))
    }

    static func window(at offset: Int64, fileSize: Int64, current: Range<Int64>?, replenishAfterRead: Bool = false, isCached: (Range<Int64>) -> Bool) -> Range<Int64>? {
        guard let probe = boundedRange(at: offset, length: probeBytes, fileSize: fileSize) else {
            return nil
        }
        if let current, current.lowerBound <= probe.lowerBound, current.upperBound >= probe.upperBound {
            if replenishAfterRead, offset - current.lowerBound >= probeBytes,
               let next = boundedRange(at: offset, length: windowBytes, fileSize: fileSize), next.upperBound > current.upperBound,
               !isCached(current.upperBound ..< next.upperBound) {
                return next
            }
            return current
        }
        if isCached(probe) {
            return current.flatMap { $0.overlaps(probe) ? $0 : nil }
        }
        return boundedRange(at: offset, length: windowBytes, fileSize: fileSize)
    }
}
