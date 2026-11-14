import Foundation
import SwiftSignalKit

private func expect(_ result: Bool, _ name: String) {
    precondition(result, name)
    print("PASS \(name)")
}

private func expectError(_ error: LocalArchiveError, _ name: String, _ body: () throws -> Void) {
    do {
        try body()
        preconditionFailure(name)
    } catch let actual as LocalArchiveError {
        expect(actual == error, name)
    } catch {
        preconditionFailure("\(name): \(error)")
    }
}

private func peer(_ namespace: Int32, _ id: Int64) -> PeerId {
    PeerId(namespace: ._internalFromInt32Value(namespace), id: ._internalFromInt64Value(id))
}

private let now: Int64 = 3_000_000
private let one = peer(1, 35)
private let two = peer(2, 35)
private let queue = Queue(name: "LocalMessageArchiveTests")
private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

private func row(_ id: Int32, _ time: Int64 = now, peer: PeerId = one, thread: Int64? = nil, kind: LocalArchiveMessage.Kind = .deletion, revision: Int64 = 1, snapshot: Data = Data([1, 2, 3])) -> LocalArchiveMessage {
    LocalArchiveMessage(id: .init(message: MessageId(peerId: peer, namespace: 0, id: id), threadId: thread, kind: kind, revision: revision), capturedAt: time, snapshot: snapshot)
}

private func box(_ path: String) -> SqliteValueBox {
    SqliteValueBox(basePath: directory.appendingPathComponent(path).path, queue: queue, isTemporary: false, isReadOnly: false, useCaches: false, removeDatabaseOnError: false, encryptionParameters: nil, upgradeProgress: { _ in })!
}

private func transact<T>(_ storage: SqliteValueBox, _ body: (LocalMessageArchive) throws -> T) rethrows -> T {
    storage.begin()
    defer { storage.commit() }
    return try body(LocalMessageArchive(valueBox: storage, accountId: 84))
}

private func onArchiveQueue<T>(_ body: () throws -> T) throws -> T {
    var result: Result<T, Error>?
    queue.sync { result = Result { try body() } }
    return try result!.get()
}

private func run() throws {
    let root = box("primary")
    let rows = [row(1, now - 20), row(1, now - 10, thread: 4), row(2, now - 10, thread: 4, kind: .edit), row(2, now - 10, thread: 4, kind: .edit, revision: 2), row(1, now - 5, peer: two)]
    let first = try transact(root) { archive in
        try archive.append(rows, now: now)
        try archive.append([row(1, now, snapshot: Data([9]))], now: now)
        let result = try archive.page(.account, before: nil, limit: 2, now: now)
        expect(result.messages == [rows[4], rows[3]], "index order and exact snapshot")
        expect(try archive.page(.chat(one), before: nil, limit: 10, now: now).messages.count == 4, "namespaced chat scope")
        expect(try archive.page(.thread(one, nil), before: nil, limit: 10, now: now).messages == [rows[0]], "nil thread scope")
        expect(try archive.page(.thread(one, 4), before: nil, limit: 10, now: now).messages.count == 3, "forum thread scope")
        expectError(.invalidCursor, "cross-scope cursor rejection") {
            _ = try archive.page(.chat(one), before: result.next, limit: 10, now: now)
        }
        return result
    }
    try transact(root) { archive in
        try archive.append([row(3)], now: now)
        expect(try archive.page(.account, before: first.next, limit: 10, now: now).messages == [rows[2], rows[1], rows[0]], "cursor stability and replay idempotence")
        expect(try archive.remove(rows[2].id), "single revision removal")
        expect(try archive.clear(.thread(one, 4), limit: 1), "bounded thread cleanup requests continuation")
        expect(!(try archive.clear(.thread(one, 4), limit: 1)), "bounded thread cleanup completes")
        expect(try archive.page(.chat(two), before: nil, limit: 10, now: now).messages == [rows[4]], "cleanup preserves other chats")
    }
    try transact(box("primary")) { archive in
        expect(try archive.page(.account, before: nil, limit: 10, now: now).messages == [row(3), rows[4], rows[0]], "persistence across reopen")
        try archive.append([row(1, now, snapshot: Data([9]))], now: now)
        expect(try archive.page(.account, before: nil, limit: 10, now: now).messages == [row(3), rows[4], rows[0]], "replay deduplication survives reopen")
        let other = LocalMessageArchive(valueBox: archive.valueBox, accountId: 85)
        expectError(.accountMismatch, "wrong account cannot read") {
            _ = try other.page(.account, before: nil, limit: 1, now: now)
        }
        let invalid = LocalMessageArchive(valueBox: archive.valueBox, accountId: 0)
        expectError(.invalidAccount, "unscoped account rejected") {
            try invalid.append([row(4)], now: now)
        }
        expectError(.invalidMessage, "invalid batch rejects all writes") {
            try archive.append([row(4), row(5, snapshot: Data())], now: now)
        }
        expect(try archive.page(.account, before: nil, limit: 10, now: now).messages.count == 3, "invalid batch leaves unchanged state")
        expect(try archive.clear(.account, limit: 1, close: true), "logout marks closed before draining")
        expectError(.closed, "late write rejected") {
            try archive.append([row(4)], now: now)
        }
    }
    try transact(box("primary")) { archive in
        expectError(.closed, "logout persists across reopen") {
            _ = try archive.page(.account, before: nil, limit: 10, now: now)
        }
        expect(!(try archive.clear(.account, limit: 10, close: true)), "logout cleanup resumes")
        expect(archive.valueBox.count(LocalMessageArchive.table) == 1, "logout leaves only closed marker")
    }
    try transact(box("retention")) { archive in
        let cutoff = now - LocalMessageArchive.retentionSeconds
        try archive.append([row(1, cutoff - 1), row(2, cutoff), row(3)], now: now)
        expect(try archive.page(.account, before: nil, limit: 10, now: now).messages == [row(3), row(2, cutoff)], "retention includes cutoff only")
        expect(try archive.page(.account, before: nil, limit: 10, now: now + 1).messages == [row(3)], "read hides expired records before pruning")
        expect(!(try archive.prune(now: now + 1)), "physical time pruning")
        expect(archive.valueBox.count(LocalMessageArchive.table) == 5, "pruning removes all indexes")
        for start in stride(from: 1, through: LocalMessageArchive.maximumRecords, by: LocalMessageArchive.maximumBatchSize) {
            let batch = (start ..< start + LocalMessageArchive.maximumBatchSize).map { row(Int32($0), kind: .edit) }
            try archive.append(batch, now: now)
        }
        expect(archive.valueBox.count(LocalMessageArchive.table) == LocalMessageArchive.maximumRecords * 4 + 1, "capacity prunes the oldest record and its indexes")
    }
    try transact(box("unsupported")) { archive in
        archive.valueBox.set(LocalMessageArchive.table, key: ValueBoxKey("M"), value: MemoryBuffer(data: Data([2])))
        expectError(.unsupportedSchema, "future schema preserved") {
            try archive.append([row(1)], now: now)
        }
        expect(archive.valueBox.count(LocalMessageArchive.table) == 1, "future schema unchanged")
    }
}

private func checkMaintenance() throws {
    let accountPeerId = peer(0, 84)
    let postbox = try onArchiveQueue { Postbox(valueBox: box("scheduled-retention"), queue: queue) }
    try onArchiveQueue {
        try transact(postbox.valueBox) { archive in
            let first = (1 ... 128).map { row(Int32($0)) }
            let second = (129 ... 260).map { row(Int32($0)) }
            try archive.append(first, now: now)
            try archive.append(Array(second.prefix(128)), now: now)
            try archive.append(Array(second.suffix(4)), now: now)
            try archive.append([row(261, now + 1)], now: now + 1)
        }
    }
    let pruned = DispatchSemaphore(value: 0)
    let prune = pruneLocalMessageArchive(postbox: postbox, accountId: accountPeerId.toInt64(), now: now + LocalMessageArchive.retentionSeconds + 1)
        .start(completed: { pruned.signal() })
    expect(pruned.wait(timeout: .now() + 5) == .success, "scheduled retention drain completes")
    prune.dispose()
    try onArchiveQueue {
        try transact(postbox.valueBox) { archive in
            expect(postbox.completedTransactions == 3, "retention commits bounded batches")
            expect(try archive.page(.account, before: nil, limit: 128, now: now + LocalMessageArchive.retentionSeconds + 1).messages == [row(261, now + 1)], "retention preserves the newest in-window row")
        }
    }

    let firstCommit = DispatchSemaphore(value: 0)
    let releaseCommit = DispatchSemaphore(value: 0)
    let interrupted = try onArchiveQueue {
        Postbox(valueBox: box("managed-logout"), queue: queue, afterCommit: { count in
            if count == 1 {
                firstCommit.signal()
                _ = releaseCommit.wait(timeout: .now() + 5)
            }
        })
    }
    try onArchiveQueue {
        try transact(interrupted.valueBox) { archive in
            try archive.append((1 ... 128).map { row(Int32($0)) }, now: now)
            try archive.append([row(129)], now: now)
        }
    }
    let first = closeLocalMessageArchive(postbox: interrupted, accountPeerId: accountPeerId).start(completed: {
        preconditionFailure("Disposed logout cleanup must not complete")
    })
    expect(firstCommit.wait(timeout: .now() + 5) == .success, "logout commits first close batch")
    first.dispose()
    releaseCommit.signal()
    queue.sync {
        transact(interrupted.valueBox) { archive in
            expect(interrupted.completedTransactions == 1 && archive.valueBox.count(LocalMessageArchive.table) == 5, "cancelled logout leaves a closed archive with remaining work")
            expectError(.closed, "capture cannot reopen interrupted logout") {
                try archive.append([row(130)], now: now)
            }
        }
    }
    let reopened = try onArchiveQueue { Postbox(valueBox: box("managed-logout"), queue: queue) }
    let closed = DispatchSemaphore(value: 0)
    let resumed = closeLocalMessageArchive(postbox: reopened, accountPeerId: accountPeerId).start(completed: { closed.signal() })
    expect(closed.wait(timeout: .now() + 5) == .success, "logout resumes from durable close marker")
    resumed.dispose()
    queue.sync {
        expect(reopened.valueBox.count(LocalMessageArchive.table) == 1, "completed logout removes remaining data before continuation")
    }
}

@main
private struct ArchiveTests {
    static func main() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try onArchiveQueue(run)
        try checkMaintenance()
    }
}
