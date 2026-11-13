import CryptoKit
import Darwin
import Foundation
import SpeechModelSupport
import XCTest

@available(macOS 10.15, *)
final class SpeechModelSupportTests: XCTestCase {
    private let revision = String(repeating: "ab", count: 20)
    private let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    func testCatalogPinsPublisherRevisionAndExactArtifactMetadata() throws {
        let publisherRevision = "80da2d8bfee42b0e836fc3a9890373e5defc00a6"
        let published: [(SpeechModelArtifact.Model, String, Int64, String)] = [
            (.whisperTiny, "ggml-tiny.bin", 77691713, "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
            (.whisperBase, "ggml-base.bin", 147951465, "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"),
            (.whisperSmall, "ggml-small.bin", 487601967, "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"),
        ]
        for (model, fileName, byteCount, sha256) in published {
            let entry = try WhisperModelCatalog.artifact(for: model)
            XCTAssertEqual(entry.sourceURL.absoluteString,
                           "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(publisherRevision)/\(fileName)")
            XCTAssertEqual(entry.sourceRevision, publisherRevision)
            XCTAssertEqual(entry.model, model)
            XCTAssertEqual(entry.byteCount, byteCount)
            XCTAssertEqual(entry.sha256, sha256)
            XCTAssertEqual(entry.architecture, .universal)
            XCTAssertEqual(entry.format, .whisperCppGGML)
            XCTAssertEqual(entry.license, .mit)
        }
    }

    func testCatalogRejectsPointerAndSameSizeSubstitute() throws {
        let entry = try WhisperModelCatalog.artifact(for: .whisperTiny)
        let pointer = Data(
            ("version https://git-lfs.github.com/spec/v1\n"
                + "oid sha256:\(entry.sha256)\n"
                + "size \(entry.byteCount)\n").utf8
        )
        try withStagedFile(pointer) { file in
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: entry)) {
                XCTAssertEqual($0 as? SpeechModelStagedFileError, .unexpectedSize)
            }
        }
        try withStagedFile(Data()) { file in
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(entry.byteCount))
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: entry)) {
                XCTAssertEqual($0 as? SpeechModelStagedFileError, .checksumMismatch)
            }
        }
    }

    func testManifestValidatesVersionRevisionAndArtifactBounds() throws {
        let pinned = try artifact(byteCount: SpeechModelArtifact.maximumByteCount)
        XCTAssertEqual(pinned.sourceRevision, revision)
        XCTAssertEqual(pinned.sha256, digest)
        XCTAssertEqual(pinned.license.rawValue, "MIT")

        XCTAssertThrowsError(try artifact(manifestVersion: 2)) {
            XCTAssertEqual($0 as? SpeechModelManifestError, .unsupportedVersion)
        }
        for badRevision in ["main", revision.uppercased(), revision + "f"] {
            XCTAssertThrowsError(try artifact(sourceRevision: badRevision)) {
                XCTAssertEqual($0 as? SpeechModelManifestError, .invalidSourceRevision)
            }
        }
        for byteCount in [Int64(0), -1, SpeechModelArtifact.maximumByteCount + 1, Int64.max] {
            XCTAssertThrowsError(try artifact(byteCount: byteCount)) {
                XCTAssertEqual($0 as? SpeechModelManifestError, .invalidByteCount)
            }
        }
        for sha256 in [String(digest.dropLast()), digest.uppercased(), "🌳" + digest] {
            XCTAssertThrowsError(try artifact(sha256: sha256)) {
                XCTAssertEqual($0 as? SpeechModelManifestError, .invalidSHA256)
            }
        }
    }

    func testManifestRejectsUnpinnedOrAmbiguousArtifactURLs() throws {
        let urls = [
            "http://models.example/resolve/\(revision)/tiny.bin",
            "https://user@models.example/resolve/\(revision)/tiny.bin",
            "https://models.example/resolve/main/tiny.bin",
            "https://models.example/resolve/\(revision)/tiny.bin?key=value",
            "https://models.example/resolve/\(revision)/tiny.bin#fragment",
            "https://models.example:8080/resolve/\(revision)/tiny.bin",
            "https://models.example/resolve/\(revision)/../main/tiny.bin",
            "https://models.example/resolve/\(revision)/%2e%2e/main/tiny.bin",
            "https://models.example/resolve/\(revision)/sub%2Fname/tiny.bin",
            "https://models.example/resolve/\(revision)",
        ]
        for url in urls {
            let parsed = try XCTUnwrap(URL(string: url))
            XCTAssertThrowsError(try artifact(sourceURL: parsed), url) {
                XCTAssertEqual($0 as? SpeechModelManifestError, .invalidSourceURL)
            }
        }
    }

    func testAcceptsKnownSHA256AndStreamsMultipleChunks() throws {
        try withStagedFile(Data("abc".utf8)) { file in
            try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: artifact())
        }
        let data = Data((0..<(2 * 256 * 1024 + 1)).map { UInt8(truncatingIfNeeded: $0) })
        let expected = try artifact(data: data)
        try withStagedFile(data) { file in
            try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: expected)
        }
    }

    func testRejectsTruncationExtensionAndEqualLengthCorruption() throws {
        for data in [Data(), Data("ab".utf8), Data("abcd".utf8)] {
            try withStagedFile(data) { file in
                XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: artifact())) {
                    XCTAssertEqual($0 as? SpeechModelStagedFileError, .unexpectedSize)
                }
            }
        }
        try withStagedFile(Data("abd".utf8)) { file in
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(at: file, against: artifact())) {
                XCTAssertEqual($0 as? SpeechModelStagedFileError, .checksumMismatch)
            }
        }
    }

    func testRejectsSymlinksHardLinksDirectoriesAndFIFOs() throws {
        try withStagedFile(Data("abc".utf8)) { file in
            let directory = file.deletingLastPathComponent()
            let symlink = directory.appendingPathComponent("symlink")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
            let fifo = directory.appendingPathComponent("fifo")
            let createdFIFO = fifo.withUnsafeFileSystemRepresentation { path in
                mkfifo(path, 0o600)
            }
            XCTAssertEqual(createdFIFO, 0)
            let hardLink = directory.appendingPathComponent("hard-link")
            try FileManager.default.linkItem(at: file, to: hardLink)
            for url in [directory, symlink, fifo, file, hardLink] {
                XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(at: url, against: artifact())) {
                    XCTAssertEqual($0 as? SpeechModelStagedFileError, .invalidStagedFile)
                }
            }
        }
    }

    func testCancellationBeforeOpeningAndBetweenChunks() throws {
        let data = Data(repeating: 7, count: 600 * 1024)
        let expected = try artifact(data: data)
        try withStagedFile(data) { file in
            let absent = file.deletingLastPathComponent().appendingPathComponent("absent")
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(
                at: absent, against: expected, isCancelled: { true }
            )) { XCTAssertTrue($0 is CancellationError) }
            var checks = 0
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(
                at: file, against: expected, isCancelled: {
                    checks += 1
                    return checks == 3
                }
            )) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(checks, 3)
        }
    }

    func testDetectsConcurrentGrowthAfterInitialSizeCheck() throws {
        let data = Data(repeating: 7, count: 600 * 1024)
        let expected = try artifact(data: data)
        try withStagedFile(data) { file in
            let writer = try FileHandle(forWritingTo: file)
            defer { try? writer.close() }
            try writer.seekToEnd()
            var checks = 0
            XCTAssertThrowsError(try SpeechModelStagedFileValidator.validateStagedBytes(
                at: file, against: expected, isCancelled: {
                    checks += 1
                    if checks == 3 {
                        do {
                            try writer.write(contentsOf: Data([9]))
                        } catch {
                            XCTFail("Could not grow the staged fixture: \(error)")
                        }
                    }
                    return false
                }
            )) { XCTAssertEqual($0 as? SpeechModelStagedFileError, .stagedFileChanged) }
        }
    }

    private func artifact(
        manifestVersion: Int = SpeechModelArtifact.currentManifestVersion,
        sourceURL: URL? = nil,
        sourceRevision: String? = nil,
        byteCount: Int64 = 3,
        sha256: String? = nil
    ) throws -> SpeechModelArtifact {
        let pinnedURL = try XCTUnwrap(URL(string: "https://models.example/resolve/\(revision)/tiny.bin"))
        return try SpeechModelArtifact(
            manifestVersion: manifestVersion, model: .whisperTiny, format: .whisperCppGGML, architecture: .universal,
            license: .mit, sourceURL: sourceURL ?? pinnedURL, sourceRevision: sourceRevision ?? revision,
            byteCount: byteCount, sha256: sha256 ?? digest
        )
    }

    private func artifact(data: Data) throws -> SpeechModelArtifact {
        try artifact(
            byteCount: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func withStagedFile(_ data: Data, body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("staged")
        try data.write(to: file)
        try body(file)
    }
}
