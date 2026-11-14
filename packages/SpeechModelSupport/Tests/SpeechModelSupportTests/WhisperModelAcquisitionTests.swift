import CryptoKit
import Foundation
import XCTest
@testable import SpeechModelSupport

@available(macOS 10.15, *)
final class WhisperModelAcquisitionTests: XCTestCase {
    private let model = SpeechModelArtifact.Model.whisperTiny
    private let bytes = Data(repeating: 23, count: 650 * 1024)

    func testImportBalancesScopeBeforeMainQueueCompletionAndReadsThroughCache() throws {
        try withFixture { cache, file in
            var events: [String] = []
            let acquisition = WhisperModelAcquisition(cache: cache, beginAccess: { received in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(received, file)
                events.append("start")
                return true
            }, endAccess: { received in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(received, file)
                events.append("stop")
            })
            let imported = expectation(description: "Import complete")
            let cancel = acquisition.importModel(from: file, for: model) { result in
                XCTAssertTrue(Thread.isMainThread)
                if case let .failure(error) = result { XCTFail("Unexpected import failure: \(error)") }
                XCTAssertEqual(events, ["start", "stop"])
                imported.fulfill()
            }
            wait(for: [imported], timeout: 5)
            cancel()
            XCTAssertEqual(try cache.withInstalledModel(model) { try $0.readToEnd() }, bytes)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testImportRejectsMismatchedBytesWithoutReplacingAndRemovesExplicitly() throws {
        try withFixture { cache, file in
            try cache.install(stagedFile: file, for: model)
            try Data(repeating: 42, count: bytes.count).write(to: file)
            let acquisition = WhisperModelAcquisition(cache: cache, beginAccess: { _ in false }, endAccess: { _ in
                XCTFail("No successful security scope to end")
            })
            let rejected = expectation(description: "Wrong same-size bytes rejected")
            _ = acquisition.importModel(from: file, for: model) { result in
                if case .failure(.modelDoesNotMatch) = result {
                    rejected.fulfill()
                } else {
                    XCTFail("Unexpected import result: \(result)")
                }
            }
            wait(for: [rejected], timeout: 5)
            XCTAssertEqual(try cache.withInstalledModel(model) { try $0.readToEnd() }, bytes)

            let removed = expectation(description: "Remove complete")
            _ = acquisition.removeModel(model) { result in
                if case let .failure(error) = result { XCTFail("Unexpected removal failure: \(error)") }
                removed.fulfill()
            }
            wait(for: [removed], timeout: 5)
            XCTAssertNil(try cache.withInstalledModel(model) { _ in true })
        }
    }

    func testCancelWhileModelIsInUseCleansScopeAndRejectsConcurrentMutation() throws {
        try withFixture { cache, file in
            try cache.install(stagedFile: file, for: model)
            let enteredScope = DispatchSemaphore(value: 0)
            let scopeEnded = expectation(description: "Security scope released")
            let cancelled = expectation(description: "Import cancelled")
            let busy = expectation(description: "Concurrent mutation rejected")
            let acquisition = WhisperModelAcquisition(cache: cache, beginAccess: { _ in
                enteredScope.signal()
                return true
            }, endAccess: { _ in scopeEnded.fulfill() })

            _ = try cache.withInstalledModel(model) { _ in
                let cancel = acquisition.importModel(from: file, for: model) { result in
                    if case .failure(.cancelled) = result {
                        cancelled.fulfill()
                    } else {
                        XCTFail("Expected cancellation, got \(result)")
                    }
                }
                XCTAssertEqual(enteredScope.wait(timeout: .now() + 5), .success)
                _ = acquisition.removeModel(model) { result in
                    if case .failure(.busy) = result {
                        busy.fulfill()
                    } else {
                        XCTFail("Expected busy, got \(result)")
                    }
                }
                cancel()
                cancel()
                wait(for: [busy, scopeEnded, cancelled], timeout: 5)
            }
            XCTAssertEqual(try cache.withInstalledModel(model) { try $0.readToEnd() }, bytes)
        }
    }

    func testImportRejectsDirectoriesAndSymlinksAndReportsMissingFile() throws {
        try withFixture { cache, file in
            let root = file.deletingLastPathComponent()
            let symlink = root.appendingPathComponent("symlink")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
            let acquisition = WhisperModelAcquisition(cache: cache, beginAccess: { _ in false }, endAccess: { _ in })
            let directory = root.appendingPathComponent("directory", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            for (url, failure) in [(symlink, WhisperModelAcquisition.Failure.invalidFile), (directory, .invalidFile),
                                   (root.appendingPathComponent("missing"), .unableToAccessFile)] {
                let rejected = expectation(description: "Invalid source rejected")
                _ = acquisition.importModel(from: url, for: model) { result in
                if case let .failure(error) = result, error == failure {
                        rejected.fulfill()
                    } else {
                        XCTFail("Expected \(failure), got \(result)")
                    }
                }
                wait(for: [rejected], timeout: 5)
            }
            XCTAssertNil(try cache.withInstalledModel(model) { _ in true })
        }
    }

    private func withFixture(_ body: (WhisperModelCache, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("selected-model")
        try bytes.write(to: file)
        let revision = String(repeating: "ab", count: 20)
        let url = try XCTUnwrap(URL(string: "https://models.example/resolve/\(revision)/model.bin"))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let byteCount = Int64(bytes.count)
        let cache = WhisperModelCache(directory: root.appendingPathComponent("WhisperModels", isDirectory: true)) { model in
            try SpeechModelArtifact(
                manifestVersion: 1, model: model, format: .whisperCppGGML, architecture: .universal,
                license: .mit, sourceURL: url, sourceRevision: revision, byteCount: byteCount, sha256: digest
            )
        }
        try body(cache, file)
    }
}
