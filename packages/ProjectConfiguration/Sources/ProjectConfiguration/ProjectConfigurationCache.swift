import Darwin
import Foundation

public struct SignedProjectConfiguration {
    public let payload: Data
    public let signature: Data
    public let keyID: String

    public init(payload: Data, signature: Data, keyID: String) {
        self.payload = payload
        self.signature = signature
        self.keyID = keyID
    }
}

public enum ProjectConfigurationCacheError: Error, Equatable {
    case invalidDirectory
    case invalidKeyIdentifier
    case invalidCacheFile
    case olderConfiguration
    case conflictingConfiguration
}

@available(macOS 10.15, *)
public struct ProjectConfigurationCache {
    private static let fileName = "gergram-project-configuration"
    private static let maximumKeyIdentifierSize = 128
    private static let recordVersion: UInt8 = 1
    private static let signatureSize = SignedProjectConfigurationVerifier.signatureSize
    private static let headerSize = 2 + signatureSize
    private static let maximumRecordSize = headerSize + maximumKeyIdentifierSize
        + SignedProjectConfigurationVerifier.maximumPayloadSize

    private let directory: URL
    private let verifier: SignedProjectConfigurationVerifier

    public init(directory: URL, verifier: SignedProjectConfigurationVerifier) {
        self.directory = directory
        self.verifier = verifier
    }

    @discardableResult
    public func store(_ record: SignedProjectConfiguration, now: Date) throws -> ProjectConfiguration {
        let verified = try verify(record, now: now)
        guard directory.isFileURL else { throw ProjectConfigurationCacheError.invalidDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = try openDirectory()
        defer { close(descriptor) }

        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw Self.fileError() }
        }
        defer { flock(descriptor, LOCK_UN) }

        if let existing = try readRecord(directory: descriptor),
           let prior = try? verifier.authenticate(payload: existing.payload, signature: existing.signature,
                                                   keyID: existing.keyID, now: now, acceptsExpired: true) {
            guard verified.issuedAtUnixSeconds >= prior.issuedAtUnixSeconds else {
                throw ProjectConfigurationCacheError.olderConfiguration
            }
            if verified.issuedAtUnixSeconds == prior.issuedAtUnixSeconds {
                guard existing.payload == record.payload else {
                    throw ProjectConfigurationCacheError.conflictingConfiguration
                }
                if existing.signature == record.signature, existing.keyID == record.keyID {
                    return verified
                }
            }
        }

        let keyID = record.keyID.utf8
        var data = Data([Self.recordVersion, UInt8(keyID.count)])
        data.append(record.signature)
        data.append(contentsOf: keyID)
        data.append(record.payload)
        try replaceRecord(data, directory: descriptor)
        return verified
    }

    public func load(now: Date, fallback: SignedProjectConfiguration? = nil) -> ProjectConfiguration? {
        let cached = try? readCached(now: now)
        return cached ?? fallback.flatMap { try? verify($0, now: now) }
    }

    private func verify(_ record: SignedProjectConfiguration, now: Date) throws -> ProjectConfiguration {
        guard !record.keyID.isEmpty, record.keyID.utf8.count <= Self.maximumKeyIdentifierSize else {
            throw ProjectConfigurationCacheError.invalidKeyIdentifier
        }
        return try verifier.verify(payload: record.payload, signature: record.signature, keyID: record.keyID, now: now)
    }

    private func readCached(now: Date) throws -> ProjectConfiguration? {
        let descriptor = try openDirectory()
        defer { close(descriptor) }
        guard let record = try readRecord(directory: descriptor) else { return nil }
        return try verify(record, now: now)
    }

    private func openDirectory() throws -> Int32 {
        guard directory.isFileURL else { throw ProjectConfigurationCacheError.invalidDirectory }
        let descriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw Self.fileError() }
        return descriptor
    }

    private func readRecord(directory descriptor: Int32) throws -> SignedProjectConfiguration? {
        let file = openat(descriptor, Self.fileName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if file < 0 {
            if errno == ENOENT { return nil }
            throw Self.fileError()
        }
        defer { close(file) }

        var metadata = stat()
        guard fstat(file, &metadata) == 0 else { throw Self.fileError() }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw ProjectConfigurationCacheError.invalidCacheFile
        }
        guard metadata.st_size > 0, metadata.st_size <= Self.maximumRecordSize else { return nil }

        var data = Data(count: Int(metadata.st_size) + 1)
        let length = try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = read(file, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += count
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    throw Self.fileError()
                }
            }
            return offset
        }
        guard length == metadata.st_size else { return nil }
        data.removeSubrange(length..<data.count)
        guard data.count > Self.headerSize, data[0] == Self.recordVersion else { return nil }
        let keyLength = Int(data[1])
        let payloadStart = Self.headerSize + keyLength
        guard (1...Self.maximumKeyIdentifierSize).contains(keyLength), payloadStart < data.count,
              let keyID = String(bytes: data[Self.headerSize..<payloadStart], encoding: .utf8) else {
            return nil
        }
        return SignedProjectConfiguration(
            payload: Data(data[payloadStart...]),
            signature: Data(data[2..<Self.headerSize]),
            keyID: keyID
        )
    }

    private func replaceRecord(_ data: Data, directory descriptor: Int32) throws {
        let temporary = ".gergram-project-configuration-\(UUID().uuidString)"
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw Self.fileError() }
        defer {
            close(file)
            unlinkat(descriptor, temporary, 0)
        }

        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = write(file, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
                if count > 0 {
                    offset += count
                } else if count == 0 || errno != EINTR {
                    throw count == 0 ? POSIXError(.EIO) : Self.fileError()
                }
            }
        }
        while fsync(file) != 0 {
            guard errno == EINTR else { throw Self.fileError() }
        }
        guard renameat(descriptor, temporary, descriptor, Self.fileName) == 0 else {
            throw Self.fileError()
        }
    }

    private static func fileError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
