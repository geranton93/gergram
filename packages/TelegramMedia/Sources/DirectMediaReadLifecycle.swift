import Foundation
import Darwin

enum DirectMediaReadPosition {
    private static let forceSeekFlag: Int32 = 0x20000

    static func seek(offset: Int64, whence: Int32, current: Int64, fileSize: Int64) -> Int64? {
        let base: Int64
        switch whence & ~self.forceSeekFlag {
        case SEEK_SET:
            base = 0
        case SEEK_CUR:
            base = current
        case SEEK_END:
            base = fileSize
        default:
            return nil
        }

        let (position, overflow) = base.addingReportingOverflow(offset)
        guard !overflow, position >= 0, position <= fileSize else {
            return nil
        }
        return position
    }
}

final class DirectMediaReadDemand {
    private let lock = NSLock()
    private var pendingTimestamp: Double?

    func submit(_ timestamp: Double) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        let needsWakeup = self.pendingTimestamp == nil
        self.pendingTimestamp = timestamp
        return needsWakeup
    }

    func take() -> Double? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let timestamp = self.pendingTimestamp
        self.pendingTimestamp = nil
        return timestamp
    }
}
