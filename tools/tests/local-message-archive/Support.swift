import Foundation

public protocol PostboxCoding {
    init(decoder: PostboxDecoder)
    func encode(_ encoder: PostboxEncoder)
}

public struct PostboxDecoder {
    public func decodeInt64ForKey(_ key: String, orElse: Int64) -> Int64 { fatalError() }
    public func decodeInt32ForKey(_ key: String, orElse: Int32) -> Int32 { fatalError() }
}

public struct PostboxEncoder {
    public func encodeInt64(_ value: Int64, forKey: String) { fatalError() }
    public func encodeInt32(_ value: Int32, forKey: String) { fatalError() }
}

func postboxLog(_ message: String) {}
func postboxLogSync() {}

func printOpenFiles() {}
