import CryptoKit
import Darwin
import Foundation

public enum SpeechModelStagedFileError: Error, Equatable {
    case invalidStagedFile
    case unexpectedSize
    case stagedFileChanged
    case checksumMismatch
}

@available(macOS 10.15, *)
public enum SpeechModelStagedFileValidator {
    private static let chunkSize = 256 * 1024

    public static func validateStagedBytes(
        at url: URL,
        against trustedArtifact: SpeechModelArtifact,
        isCancelled: () -> Bool = { false }
    ) throws {
        if isCancelled() { throw CancellationError() }
        guard url.isFileURL else { throw SpeechModelStagedFileError.invalidStagedFile }

        let descriptor = try url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { throw SpeechModelStagedFileError.invalidStagedFile }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            if descriptor < 0 {
                if errno == ELOOP { throw SpeechModelStagedFileError.invalidStagedFile }
                throw fileError()
            }
            return descriptor
        }
        defer { close(descriptor) }

        var original = stat()
        guard fstat(descriptor, &original) == 0 else { throw fileError() }
        guard (original.st_mode & S_IFMT) == S_IFREG, original.st_nlink == 1 else {
            throw SpeechModelStagedFileError.invalidStagedFile
        }
        guard original.st_size == trustedArtifact.byteCount else {
            throw SpeechModelStagedFileError.unexpectedSize
        }

        var hash = SHA256()
        var remaining = trustedArtifact.byteCount
        var chunk = [UInt8](repeating: 0, count: min(chunkSize, Int(remaining) + 1))
        while true {
            if isCancelled() { throw CancellationError() }
            let count = try chunk.withUnsafeMutableBytes { bytes -> Int in
                let count = read(descriptor, bytes.baseAddress, min(bytes.count, Int(remaining) + 1))
                if count < 0, errno != EINTR { throw fileError() }
                if count > remaining { throw SpeechModelStagedFileError.stagedFileChanged }
                if count > 0 {
                    hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: bytes.prefix(count)))
                }
                return count
            }
            if count == 0 { break }
            if count > 0 { remaining -= Int64(count) }
        }

        if isCancelled() { throw CancellationError() }
        var current = stat()
        guard fstat(descriptor, &current) == 0 else { throw fileError() }
        guard remaining == 0, current.st_size == original.st_size, current.st_nlink == original.st_nlink,
              current.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
              current.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec,
              current.st_ctimespec.tv_sec == original.st_ctimespec.tv_sec,
              current.st_ctimespec.tv_nsec == original.st_ctimespec.tv_nsec else {
            throw SpeechModelStagedFileError.stagedFileChanged
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == trustedArtifact.sha256 else {
            throw SpeechModelStagedFileError.checksumMismatch
        }
    }

    private static func fileError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
