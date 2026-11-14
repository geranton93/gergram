import CryptoKit
import Darwin
import Foundation
import ProjectConfiguration
import XCTest

@available(macOS 10.15, *)
final class ProjectConfigurationCacheTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fileName = "gergram-project-configuration"

    private var verifier: SignedProjectConfigurationVerifier {
        SignedProjectConfigurationVerifier(audience: "gergram-test", trustedKeys: ["active": key.publicKey])
    }

    private func withCache(_ body: (URL, ProjectConfigurationCache) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory, ProjectConfigurationCache(directory: directory, verifier: verifier))
    }

    private func record(
        id: Int64 = 1, issuedAt: Int64 = 1_800_000_000, expiresAt: Int64 = 1_800_000_600,
        keyID: String = "active", signingKey: Curve25519.Signing.PrivateKey? = nil
    ) throws -> SignedProjectConfiguration {
        let payload = Data("[1,\"gergram-test\",\(issuedAt),\(expiresAt),[[\"user\",\"\(id)\",\"developer\"]]]".utf8)
        return SignedProjectConfiguration(payload: payload, signature: try (signingKey ?? key).signature(for: payload), keyID: keyID)
    }

    func testPersistsAndReverifiesWithCurrentTrustAndTime() throws {
        try withCache { directory, cache in
            XCTAssertNil(cache.load(now: now))
            let signed = try record()
            let verified = try cache.store(signed, now: now)
            let reopened = ProjectConfigurationCache(directory: directory, verifier: verifier)
            XCTAssertEqual(reopened.load(now: now), verified)
            XCTAssertNil(reopened.load(now: verified.expiresAt))

            let withoutKey = SignedProjectConfigurationVerifier(audience: "gergram-test", trustedKeys: [:])
            let revoked = ProjectConfigurationCache(directory: directory, verifier: withoutKey)
            XCTAssertNil(revoked.load(now: now, fallback: signed))

            let otherAudience = SignedProjectConfigurationVerifier(audience: "different", trustedKeys: ["active": key.publicKey])
            let other = ProjectConfigurationCache(directory: directory, verifier: otherAudience)
            XCTAssertNil(other.load(now: now, fallback: signed))
        }
    }

    func testRejectsInvalidAndOlderWritesWithoutReplacingLastGood() throws {
        try withCache { directory, cache in
            let latest = try record(id: 2)
            let verified = try cache.store(latest, now: now)
            let file = directory.appendingPathComponent(fileName)
            let original = try Data(contentsOf: file)
            let forged = try record(id: 3, signingKey: Curve25519.Signing.PrivateKey())
            XCTAssertThrowsError(try cache.store(forged, now: now)) {
                XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .invalidSignature)
            }
            XCTAssertThrowsError(try cache.store(record(issuedAt: 1_799_999_999), now: now)) {
                XCTAssertEqual($0 as? ProjectConfigurationCacheError, .olderConfiguration)
            }
            XCTAssertThrowsError(try cache.store(record(id: 3), now: now)) {
                XCTAssertEqual($0 as? ProjectConfigurationCacheError, .conflictingConfiguration)
            }
            XCTAssertEqual(try cache.store(latest, now: now), verified)
            XCTAssertEqual(try Data(contentsOf: file), original)
            XCTAssertEqual(cache.load(now: now), verified)
        }
    }

    func testExpiredCacheStillRejectsOlderReplacementAndLoadsValidFallback() throws {
        try withCache { _, cache in
            let expired = try record(id: 2, expiresAt: 1_800_000_001)
            try cache.store(expired, now: now)
            let later = now.addingTimeInterval(1)
            let fallback = try record(id: 1, issuedAt: 1_799_999_999)
            XCTAssertEqual(cache.load(now: later, fallback: fallback)?.badges[.init(kind: .user, id: 1)], .developer)
            XCTAssertNil(cache.load(now: later, fallback: expired))
            XCTAssertThrowsError(try cache.store(fallback, now: later)) {
                XCTAssertEqual($0 as? ProjectConfigurationCacheError, .olderConfiguration)
            }
        }
    }

    func testCorruptAndOversizedFilesFallBackAndCanRecover() throws {
        try withCache { directory, cache in
            let valid = try record()
            let result = try cache.store(valid, now: now)
            let file = directory.appendingPathComponent(fileName)
            var tampered = try Data(contentsOf: file)
            tampered[tampered.count - 1] = 32
            try tampered.write(to: file)
            XCTAssertNil(cache.load(now: now))
            XCTAssertEqual(cache.load(now: now, fallback: valid), result)

            try Data(repeating: 0, count: 256 * 1024).write(to: file)
            XCTAssertNil(cache.load(now: now))
            XCTAssertEqual(cache.load(now: now, fallback: valid), result)
            XCTAssertEqual(try cache.store(valid, now: now), result)
            XCTAssertEqual(cache.load(now: now), result)
        }
    }

    func testRejectsNonregularAndLinkedCacheFiles() throws {
        try withCache { directory, cache in
            let valid = try record()
            let result = try cache.store(valid, now: now)
            let file = directory.appendingPathComponent(fileName)
            let target = directory.appendingPathComponent("target")
            try FileManager.default.moveItem(at: file, to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertNil(cache.load(now: now))
            XCTAssertThrowsError(try cache.store(valid, now: now))
            XCTAssertEqual(cache.load(now: now, fallback: valid), result)

            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(file.path.withCString { mkfifo($0, 0o600) }, 0)
            XCTAssertNil(cache.load(now: now))
            XCTAssertThrowsError(try cache.store(valid, now: now)) {
                XCTAssertEqual($0 as? ProjectConfigurationCacheError, .invalidCacheFile)
            }
        }
    }

    func testReadersObserveOnlyWholeAuthenticatedRecordsDuringReplacement() throws {
        try withCache { directory, cache in
            let records = try (1...12).map { index in
                try record(id: Int64(index), issuedAt: 1_800_000_000 + Int64(index))
            }
            try cache.store(records[0], now: now)
            let failureLock = NSLock()
            var failures: [String] = []
            DispatchQueue.concurrentPerform(iterations: 4) { index in
                let worker = ProjectConfigurationCache(directory: directory, verifier: verifier)
                if index == 0 {
                    do {
                        for record in records.dropFirst() {
                            try worker.store(record, now: now)
                        }
                    } catch {
                        failureLock.lock()
                        failures.append(String(describing: error))
                        failureLock.unlock()
                    }
                } else {
                    for _ in 0..<20 {
                        let badges = worker.load(now: now)?.badges
                        if badges?.count != 1 || badges?.values.first != .developer {
                            failureLock.lock()
                            failures.append("An incomplete or unauthenticated record was visible")
                            failureLock.unlock()
                        }
                    }
                }
            }
            XCTAssertTrue(failures.isEmpty, String(describing: failures))
            XCTAssertEqual(cache.load(now: now)?.badges, [.init(kind: .user, id: 12): .developer])
        }
    }

    func testConcurrentWritersKeepNewestAuthenticatedRecord() throws {
        try withCache { directory, cache in
            let records = try (1...12).map { index in
                try record(id: Int64(index), issuedAt: 1_800_000_000 + Int64(index))
            }
            let failureLock = NSLock()
            var failures: [Error] = []
            DispatchQueue.concurrentPerform(iterations: records.count) { index in
                do {
                    let writer = ProjectConfigurationCache(directory: directory, verifier: verifier)
                    try writer.store(records[index], now: now)
                } catch ProjectConfigurationCacheError.olderConfiguration {
                } catch {
                    failureLock.lock()
                    failures.append(error)
                    failureLock.unlock()
                }
            }
            XCTAssertTrue(failures.isEmpty, String(describing: failures))
            XCTAssertEqual(cache.load(now: now)?.badges, [.init(kind: .user, id: 12): .developer])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [fileName])
        }
    }
}
