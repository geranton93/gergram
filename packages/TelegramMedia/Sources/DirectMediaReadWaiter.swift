import Foundation

final class DirectMediaReadWaiter {
    enum Outcome: Equatable {
        case bytes(Data)
        case cancelled
        case failed
    }

    private let condition = NSCondition()
    private var outcome: Outcome?

    func receive(_ data: Data?) {
        resolve(data.map(Outcome.bytes) ?? .failed)
    }

    func cancel() {
        resolve(.cancelled)
    }

    func fetchFinished(requestedBytesOnDisk: Bool) {
        if !requestedBytesOnDisk {
            resolve(.failed)
        }
    }

    func wait() -> Outcome {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let outcome {
                return outcome
            }
            condition.wait()
        }
    }

    private func resolve(_ outcome: Outcome) {
        condition.lock()
        defer { condition.unlock() }
        guard self.outcome == nil else {
            return
        }
        self.outcome = outcome
        condition.signal()
    }
}
