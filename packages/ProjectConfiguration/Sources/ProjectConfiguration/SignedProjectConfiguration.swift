import CryptoKit
import Foundation

public struct ProjectConfiguration: Equatable {
    let issuedAtUnixSeconds: Int64
    public let expiresAt: Date
    public let badges: [Peer: Badge]

    public struct Peer: Hashable {
        public enum Kind: String, Decodable {
            case user
            case channel
        }

        public let kind: Kind
        public let id: Int64

        public init(kind: Kind, id: Int64) {
            self.kind = kind
            self.id = id
        }
    }

    public enum Badge: String, Decodable {
        case community
        case developer
        case supporter
    }
}

public enum ProjectConfigurationVerificationError: Error, Equatable {
    case invalidPayloadSize
    case unknownKey
    case invalidSignature
    case malformedPayload
    case unsupportedVersion
    case wrongAudience
    case invalidValidityWindow
    case invalidBadges
}

@available(macOS 10.15, *)
public struct SignedProjectConfigurationVerifier {
    static let maximumPayloadSize = 192 * 1024
    static let signatureSize = 64
    private static let maximumBadgeCount = 4096
    private static let maximumLifetime: Int64 = 30 * 24 * 60 * 60
    private static let maximumClockSkew: TimeInterval = 5 * 60

    private let audience: String
    private let trustedKeys: [String: Curve25519.Signing.PublicKey]

    public init(audience: String, trustedKeys: [String: Curve25519.Signing.PublicKey]) {
        self.audience = audience
        self.trustedKeys = trustedKeys
    }

    public func verify(payload: Data, signature: Data, keyID: String, now: Date) throws -> ProjectConfiguration {
        try authenticate(payload: payload, signature: signature, keyID: keyID, now: now, acceptsExpired: false)
    }

    func authenticate(payload: Data, signature: Data, keyID: String, now: Date, acceptsExpired: Bool) throws -> ProjectConfiguration {
        guard !payload.isEmpty, payload.count <= Self.maximumPayloadSize else {
            throw ProjectConfigurationVerificationError.invalidPayloadSize
        }
        guard let key = trustedKeys[keyID] else {
            throw ProjectConfigurationVerificationError.unknownKey
        }
        guard signature.count == Self.signatureSize, key.isValidSignature(signature, for: payload) else {
            throw ProjectConfigurationVerificationError.invalidSignature
        }

        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: payload)
        } catch let error as ProjectConfigurationVerificationError {
            throw error
        } catch {
            throw ProjectConfigurationVerificationError.malformedPayload
        }

        guard !audience.isEmpty, decoded.audience.utf8.elementsEqual(audience.utf8) else {
            throw ProjectConfigurationVerificationError.wrongAudience
        }
        let timestamp = now.timeIntervalSince1970
        guard timestamp.isFinite,
              decoded.issuedAt > 0,
              decoded.expiresAt > decoded.issuedAt,
              decoded.expiresAt - decoded.issuedAt <= Self.maximumLifetime,
              Double(decoded.issuedAt) <= timestamp + Self.maximumClockSkew,
              acceptsExpired || Double(decoded.expiresAt) > timestamp else {
            throw ProjectConfigurationVerificationError.invalidValidityWindow
        }
        return ProjectConfiguration(
            issuedAtUnixSeconds: decoded.issuedAt,
            expiresAt: Date(timeIntervalSince1970: Double(decoded.expiresAt)),
            badges: decoded.badges
        )
    }

    private struct Payload: Decodable {
        let audience: String
        let issuedAt: Int64
        let expiresAt: Int64
        let badges: [ProjectConfiguration.Peer: ProjectConfiguration.Badge]

        init(from decoder: Decoder) throws {
            var fields = try decoder.unkeyedContainer()
            guard try fields.decode(Int.self) == 1 else {
                throw ProjectConfigurationVerificationError.unsupportedVersion
            }
            audience = try fields.decode(String.self)
            issuedAt = try fields.decode(Int64.self)
            expiresAt = try fields.decode(Int64.self)

            var entries = try fields.nestedUnkeyedContainer()
            if let count = entries.count, count > maximumBadgeCount {
                throw ProjectConfigurationVerificationError.invalidBadges
            }
            var decodedBadges: [ProjectConfiguration.Peer: ProjectConfiguration.Badge] = [:]
            while !entries.isAtEnd {
                guard decodedBadges.count < maximumBadgeCount else {
                    throw ProjectConfigurationVerificationError.invalidBadges
                }
                var entry = try entries.nestedUnkeyedContainer()
                let kind = try entry.decode(ProjectConfiguration.Peer.Kind.self)
                let idText = try entry.decode(String.self)
                let badge = try entry.decode(ProjectConfiguration.Badge.self)
                guard entry.isAtEnd else {
                    throw ProjectConfigurationVerificationError.malformedPayload
                }
                guard idText.utf8.count <= 19,
                      idText.utf8.first != 48,
                      idText.utf8.allSatisfy({ (48...57).contains($0) }),
                      let id = Int64(idText), id > 0 else {
                    throw ProjectConfigurationVerificationError.invalidBadges
                }
                let peer = ProjectConfiguration.Peer(kind: kind, id: id)
                guard decodedBadges.updateValue(badge, forKey: peer) == nil else {
                    throw ProjectConfigurationVerificationError.invalidBadges
                }
            }
            guard fields.isAtEnd else {
                throw ProjectConfigurationVerificationError.malformedPayload
            }
            badges = decodedBadges
        }
    }
}
