import CryptoKit
import Foundation
import XCTest
import ProjectConfiguration

@available(macOS 10.15, *)
final class SignedProjectConfigurationTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let audience = "gergram-test"

    private var verifier: SignedProjectConfigurationVerifier {
        SignedProjectConfigurationVerifier(audience: audience, trustedKeys: ["active": signingKey.publicKey])
    }

    private func payload(
        version: Int = 1, audience: String = "gergram-test", issuedAt: Int64 = 1_800_000_000,
        expiresAt: Int64 = 1_800_000_600, entries: String = #"["user","42","developer"]"#
    ) -> Data {
        Data("[\(version),\"\(audience)\",\(issuedAt),\(expiresAt),[\(entries)]]".utf8)
    }

    private func verified(_ payload: Data) throws -> ProjectConfiguration {
        try verifier.verify(payload: payload, signature: signingKey.signature(for: payload), keyID: "active", now: now)
    }

    private func assertRejection(
        _ payload: Data, _ expected: ProjectConfigurationVerificationError, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try verified(payload), file: file, line: line) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, expected, file: file, line: line)
        }
    }

    func testAcceptsSignedPayloadAndKeepsPeerNamespacesDistinct() throws {
        let result = try verified(payload(entries: #"["user","42","developer"],["channel","42","community"],["user","9223372036854775807","supporter"]"#))
        XCTAssertEqual(result.expiresAt, Date(timeIntervalSince1970: 1_800_000_600))
        XCTAssertEqual(result.badges, [
            .init(kind: .user, id: 42): .developer,
            .init(kind: .channel, id: 42): .community,
            .init(kind: .user, id: .max): .supporter,
        ])
    }

    func testVerifiesExactBytesAndRejectsWrongSigningKey() throws {
        let data = payload()
        let signature = try signingKey.signature(for: data)
        let other = Curve25519.Signing.PrivateKey()
        let rotated = SignedProjectConfigurationVerifier(
            audience: audience, trustedKeys: ["active": signingKey.publicKey, "next": other.publicKey]
        )
        let nextSignature = try other.signature(for: data)
        XCTAssertNoThrow(try rotated.verify(payload: data, signature: nextSignature, keyID: "next", now: now))
        XCTAssertThrowsError(try rotated.verify(payload: data, signature: signature, keyID: "next", now: now)) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .invalidSignature)
        }
        XCTAssertThrowsError(try verifier.verify(payload: data, signature: signature, keyID: "next", now: now)) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .unknownKey)
        }

        let respacedData = data + Data([32])
        XCTAssertThrowsError(try verifier.verify(payload: respacedData, signature: signature, keyID: "active", now: now)) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .invalidSignature)
        }
        XCTAssertNoThrow(try verified(respacedData))
        XCTAssertThrowsError(try verifier.verify(payload: data, signature: Data(signature.dropLast()), keyID: "active", now: now)) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .invalidSignature)
        }
    }

    func testRejectsUntrustedBytesBeforeDecoding() throws {
        XCTAssertThrowsError(try verifier.verify(payload: Data("not JSON".utf8), signature: Data(repeating: 0, count: 64), keyID: "active", now: now)) {
            XCTAssertEqual($0 as? ProjectConfigurationVerificationError, .invalidSignature)
        }
        assertRejection(Data("not JSON".utf8), .malformedPayload)
        assertRejection(Data(), .invalidPayloadSize)
        assertRejection(Data(repeating: 32, count: 192 * 1024 + 1), .invalidPayloadSize)
    }

    func testRejectsUnknownSchemaAudienceAndObjectFields() {
        assertRejection(payload(version: 2), .unsupportedVersion)
        assertRejection(payload(audience: "different-product"), .wrongAudience)
        assertRejection(Data(#"[1,"gergram-test",1800000000,1800000600,[],"extra"]"#.utf8), .malformedPayload)
        assertRejection(Data(#"{"version":2,"version":1,"audience":"gergram-test","issuedAt":1800000000,"expiresAt":1800000600,"badges":[]}"#.utf8), .malformedPayload)
        assertRejection(payload(entries: #"["user","42","developer","extra"]"#), .malformedPayload)
        assertRejection(payload(entries: #"{"kind":"user","id":"42","badge":"developer"}"#), .malformedPayload)
        assertRejection(payload(entries: #"["group","42","developer"]"#), .malformedPayload)
        assertRejection(payload(entries: #"["user","42","telegramVerified"]"#), .malformedPayload)
    }

    func testRejectsInvalidValidityWindows() {
        assertRejection(payload(issuedAt: 1_799_999_999, expiresAt: 1_800_000_000), .invalidValidityWindow)
        assertRejection(payload(issuedAt: 1_800_000_301), .invalidValidityWindow)
        assertRejection(payload(expiresAt: 1_800_000_000 + 30 * 24 * 60 * 60 + 1), .invalidValidityWindow)
        assertRejection(payload(issuedAt: 0), .invalidValidityWindow)
        assertRejection(payload(issuedAt: .min, expiresAt: .max), .invalidValidityWindow)
        XCTAssertNoThrow(try verified(payload(issuedAt: 1_800_000_300)))
        XCTAssertNoThrow(try verified(payload(expiresAt: 1_800_000_000 + 30 * 24 * 60 * 60)))
    }

    func testRejectsDuplicateAndNoncanonicalBadgeIds() {
        assertRejection(payload(entries: #"["user","42","developer"],["user","42","supporter"]"#), .invalidBadges)
        for invalid in ["0", "042", "-42", "+42", "４２", "9223372036854775808"] {
            assertRejection(payload(entries: "[\"user\",\"\(invalid)\",\"developer\"]"), .invalidBadges)
        }
        assertRejection(payload(entries: #"["user",42,"developer"]"#), .malformedPayload)
    }

    func testBadgeLimitAndEmptyConfiguration() throws {
        let entries = (1...4097).map { "[\"user\",\"\($0)\",\"community\"]" }
        let allowed = try verified(payload(entries: entries.dropLast().joined(separator: ",")))
        XCTAssertEqual(allowed.badges.count, 4096)
        assertRejection(payload(entries: entries.joined(separator: ",")), .invalidBadges)
        XCTAssertTrue(try verified(payload(entries: "")).badges.isEmpty)
    }
}
