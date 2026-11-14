import Foundation
import SwiftSignalKit

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

final class Logger {
    static let shared = Logger()

    func log(_ category: String, _ message: String) {}
}

final class Transaction {
    let valueBox: SqliteValueBox

    init(valueBox: SqliteValueBox) {
        self.valueBox = valueBox
    }

    func closeAndClearLocalArchive(accountId: Int64, limit: Int) throws -> Bool {
        try LocalMessageArchive(valueBox: self.valueBox, accountId: accountId).clear(.account, limit: limit, close: true)
    }

    func pruneLocalArchive(accountId: Int64, now: Int64) throws -> Bool {
        try LocalMessageArchive(valueBox: self.valueBox, accountId: accountId).prune(now: now)
    }
}

final class Postbox {
    private let valueBoxReference: Unmanaged<SqliteValueBox>
    var valueBox: SqliteValueBox {
        self.valueBoxReference.takeUnretainedValue()
    }
    private let queue: Queue
    private let afterCommit: ((Int) -> Void)?
    private(set) var completedTransactions = 0

    init(valueBox: SqliteValueBox, queue: Queue, afterCommit: ((Int) -> Void)? = nil) {
        self.valueBoxReference = .passRetained(valueBox)
        self.queue = queue
        self.afterCommit = afterCommit
    }

    deinit {
        let valueBoxReference = self.valueBoxReference
        self.queue.async { valueBoxReference.release() }
    }

    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.queue.justDispatch {
                self.valueBox.begin()
                let result = f(Transaction(valueBox: self.valueBox))
                self.valueBox.commit()
                self.completedTransactions += 1
                self.afterCommit?(self.completedTransactions)
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
}
