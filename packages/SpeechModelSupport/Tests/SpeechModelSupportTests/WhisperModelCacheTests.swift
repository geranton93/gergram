import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import SpeechModelSupport

@available(macOS 10.15, *)
final class WhisperModelCacheTests: XCTestCase {
    private let content = Data(repeating: 71, count: 600 * 1024)

    func testInstallReadsExactBytesAndRemoveIsIdempotent() throws {
        try withFixture { cache, directory, source in
            XCTAssertNil(try cache.withInstalledModel(.whisperTiny) { _ in true })
            try cache.remove(.whisperTiny)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

            try cache.install(stagedFile: source, for: .whisperTiny)
            try cache.install(stagedFile: source, for: .whisperBase)
            XCTAssertEqual(try cache.withInstalledModel(.whisperTiny) { try $0.readToEnd() }, content)
            XCTAssertEqual(try cache.withInstalledModel(.whisperBase) { try $0.readToEnd() }, content)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
                           ["whisperBase.bin", "whisperTiny.bin"])
            XCTAssertEqual(try Data(contentsOf: source), content)

            try cache.remove(.whisperTiny)
            try cache.remove(.whisperTiny)
            XCTAssertNil(try cache.withInstalledModel(.whisperTiny) { _ in true })
            XCTAssertEqual(try cache.withInstalledModel(.whisperBase) { try $0.readToEnd() }, content)
        }
    }

    func testInvalidReplacementAndCancellationPreserveInstalledModel() throws {
        try withFixture { cache, directory, source in
            try cache.install(stagedFile: source, for: .whisperTiny)
            let corrupt = source.deletingLastPathComponent().appendingPathComponent("corrupt")
            try Data(repeating: 82, count: content.count).write(to: corrupt)
            XCTAssertThrowsError(try cache.install(stagedFile: corrupt, for: .whisperTiny)) {
                XCTAssertEqual($0 as? SpeechModelStagedFileError, .checksumMismatch)
            }
            XCTAssertThrowsError(try cache.install(stagedFile: source, for: .whisperTiny, isCancelled: {
                let temporary = directory.appendingPathComponent(".installing")
                let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path)
                return (attributes?[.size] as? Int ?? 0) > 0
            })) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertThrowsError(try cache.install(stagedFile: source, for: .whisperTiny, isCancelled: {
                let temporary = directory.appendingPathComponent(".installing")
                let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path)
                return attributes?[.posixPermissions] as? Int == 0o400
            })) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(try cache.withInstalledModel(.whisperTiny) { try $0.readToEnd() }, content)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["whisperTiny.bin"])
        }
    }

    func testReaderRejectsCorruptionAndSymlinkWithoutCallingConsumer() throws {
        try withFixture { cache, directory, source in
            try cache.install(stagedFile: source, for: .whisperTiny)
            let active = directory.appendingPathComponent("whisperTiny.bin")
            try FileManager.default.removeItem(at: active)
            try Data(repeating: 82, count: content.count).write(to: active)
            XCTAssertThrowsError(try cache.withInstalledModel(.whisperTiny) { _ in
                XCTFail("Corrupt content reached the reader")
            }) { XCTAssertEqual($0 as? SpeechModelStagedFileError, .checksumMismatch) }

            try FileManager.default.removeItem(at: active)
            try FileManager.default.createSymbolicLink(at: active, withDestinationURL: source)
            XCTAssertThrowsError(try cache.withInstalledModel(.whisperTiny) { _ in
                XCTFail("A symlink reached the reader")
            }) { XCTAssertEqual($0 as? SpeechModelStagedFileError, .invalidStagedFile) }

            try cache.remove(.whisperTiny)
            XCTAssertEqual(try Data(contentsOf: source), content)
        }
    }

    func testRejectsCacheDirectorySymlinkAndNonPrivatePermissions() throws {
        try withFixture { cache, directory, source in
            let other = directory.deletingLastPathComponent().appendingPathComponent("other")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: other)
            XCTAssertThrowsError(try cache.install(stagedFile: source, for: .whisperTiny)) {
                XCTAssertEqual($0 as? WhisperModelCacheError, .invalidCacheDirectory)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.path), [])
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o755])
            XCTAssertThrowsError(try cache.install(stagedFile: source, for: .whisperTiny)) {
                XCTAssertEqual($0 as? WhisperModelCacheError, .invalidCacheDirectory)
            }
        }
    }

    func testInterruptedStagingRecoversAndActivationFailureCleansUp() throws {
        try withFixture { cache, directory, source in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try Data([0]).write(to: directory.appendingPathComponent(".installing"))
            try cache.install(stagedFile: source, for: .whisperTiny)
            XCTAssertEqual(try cache.withInstalledModel(.whisperTiny) { try $0.readToEnd() }, content)
            let obstruction = directory.appendingPathComponent("whisperBase.bin")
            try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: false)
            XCTAssertThrowsError(try cache.install(stagedFile: source, for: .whisperBase))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
                           ["whisperBase.bin", "whisperTiny.bin"])
            XCTAssertEqual(try cache.withInstalledModel(.whisperTiny) { try $0.readToEnd() }, content)
        }
    }

    func testConcurrentRemovalCanCancelWhileReaderOwnsDescriptor() throws {
        try withFixture { cache, directory, source in
            try cache.install(stagedFile: source, for: .whisperTiny)
            let removal = expectation(description: "Contending removal stopped")
            let otherCache = WhisperModelCache(directory: directory)
            let observed = try cache.withInstalledModel(.whisperTiny) { handle -> Data? in
                let descriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else { return -1 }
                    return open(path, O_RDONLY | O_DIRECTORY)
                }
                XCTAssertGreaterThanOrEqual(descriptor, 0)
                defer { close(descriptor) }
                XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), -1)
                XCTAssertEqual(errno, EWOULDBLOCK)
                DispatchQueue.global().async {
                    var checks = 0
                    do {
                        try otherCache.remove(.whisperTiny, isCancelled: {
                            checks += 1
                            return checks == 2
                        })
                        XCTFail("Removal completed during an active reader")
                    } catch {
                        XCTAssertTrue(error is CancellationError)
                    }
                    removal.fulfill()
                }
                wait(for: [removal], timeout: 5)
                return try handle.readToEnd()
            }
            XCTAssertEqual(observed, content)
            try cache.remove(.whisperTiny)
            XCTAssertNil(try cache.withInstalledModel(.whisperTiny) { _ in true })
        }
    }

    func testCatalogRevisionReplacementRetiresPriorBytes() throws {
        try withFixture { previous, directory, source in
            try previous.install(stagedFile: source, for: .whisperTiny)
            let newContent = Data(repeating: 99, count: content.count)
            try newContent.write(to: source)
            let updated = try makeCache(in: directory, content: newContent, revision: String(repeating: "cd", count: 20))
            try updated.install(stagedFile: source, for: .whisperTiny)
            XCTAssertEqual(try updated.withInstalledModel(.whisperTiny) { try $0.readToEnd() }, newContent)
            XCTAssertThrowsError(try previous.withInstalledModel(.whisperTiny) { _ in
                XCTFail("Retired content remained active")
            }) { XCTAssertEqual($0 as? SpeechModelStagedFileError, .checksumMismatch) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["whisperTiny.bin"])
        }
    }

    func testConcurrentInstallsPublishOnlyCompleteFiles() throws {
        try withFixture { cache, directory, source in
            let complete = expectation(description: "Concurrent installs and reads finished")
            complete.expectedFulfillmentCount = 8
            let expected = content
            for _ in 0..<8 {
                DispatchQueue.global().async {
                    defer { complete.fulfill() }
                    do {
                        try cache.install(stagedFile: source, for: .whisperTiny)
                        let bytes = try cache.withInstalledModel(.whisperTiny) { try $0.readToEnd() }
                        XCTAssertEqual(bytes, expected)
                    } catch {
                        XCTFail("Concurrent access failed: \(error)")
                    }
                }
            }
            wait(for: [complete], timeout: 10)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["whisperTiny.bin"])
        }
    }

    private func withFixture(_ body: (WhisperModelCache, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("staged")
        let directory = root.appendingPathComponent("models")
        try content.write(to: source)
        let cache = try makeCache(in: directory, content: content, revision: String(repeating: "ab", count: 20))
        try body(cache, directory, source)
    }

    private func makeCache(in directory: URL, content: Data, revision: String) throws -> WhisperModelCache {
        let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let byteCount = Int64(content.count)
        let url = try XCTUnwrap(URL(string: "https://models.example/resolve/\(revision)/model.bin"))
        return WhisperModelCache(directory: directory) { model in
            try SpeechModelArtifact(
                manifestVersion: 1, model: model, format: .whisperCppGGML, architecture: .universal,
                license: .mit, sourceURL: url, sourceRevision: revision, byteCount: byteCount, sha256: digest
            )
        }
    }
}
