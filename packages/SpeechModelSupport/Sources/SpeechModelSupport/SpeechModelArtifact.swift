import Foundation

public enum SpeechModelManifestError: Error, Equatable {
    case unsupportedVersion
    case invalidSourceRevision
    case invalidSourceURL
    case invalidByteCount
    case invalidSHA256
}

public struct SpeechModelArtifact: Equatable {
    public enum Model: String {
        case whisperTiny
        case whisperBase
        case whisperSmall
    }

    public enum Format: String {
        case whisperCppGGML
    }

    public enum Architecture: String {
        case arm64
        case x86_64
        case universal
    }

    public enum License: String {
        case mit = "MIT"
    }

    public static let currentManifestVersion = 1
    public static let maximumByteCount: Int64 = 1024 * 1024 * 1024

    public let model: Model
    public let format: Format
    public let architecture: Architecture
    public let license: License
    public let sourceURL: URL
    public let sourceRevision: String
    public let byteCount: Int64
    public let sha256: String

    public init(
        manifestVersion: Int,
        model: Model,
        format: Format,
        architecture: Architecture,
        license: License,
        sourceURL: URL,
        sourceRevision: String,
        byteCount: Int64,
        sha256: String
    ) throws {
        guard manifestVersion == Self.currentManifestVersion else {
            throw SpeechModelManifestError.unsupportedVersion
        }
        guard Self.isLowercaseHex(sourceRevision, byteCount: 40) else {
            throw SpeechModelManifestError.invalidSourceRevision
        }
        guard sourceURL.absoluteString.utf8.count <= 2048,
              let source = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              source.scheme?.lowercased() == "https", source.host?.isEmpty == false,
              source.user == nil, source.password == nil, source.query == nil, source.fragment == nil,
              source.port == nil || source.port == 443,
              Self.hasPinnedPath(source.percentEncodedPath, revision: sourceRevision) else {
            throw SpeechModelManifestError.invalidSourceURL
        }
        guard (1...Self.maximumByteCount).contains(byteCount) else {
            throw SpeechModelManifestError.invalidByteCount
        }
        guard Self.isLowercaseHex(sha256, byteCount: 64) else {
            throw SpeechModelManifestError.invalidSHA256
        }

        self.model = model
        self.format = format
        self.architecture = architecture
        self.license = license
        self.sourceURL = sourceURL
        self.sourceRevision = sourceRevision
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    private static func isLowercaseHex(_ value: String, byteCount: Int) -> Bool {
        value.utf8.count == byteCount && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func hasPinnedPath(_ path: String, revision: String) -> Bool {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        return segments.dropLast().contains(Substring(revision)) && segments.allSatisfy { segment in
            !segment.isEmpty && segment != "." && segment != ".."
                && segment.utf8.allSatisfy { byte in
                    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                        || byte == 45 || byte == 46 || byte == 95 || byte == 126
                }
        }
    }
}
