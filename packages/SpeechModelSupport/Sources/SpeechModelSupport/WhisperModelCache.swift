import Darwin
import Foundation

public enum WhisperModelCacheError: Error, Equatable {
    case invalidCacheDirectory
}

@available(macOS 10.15, *)
public struct WhisperModelCache {
    private static let installationName = ".installing"
    private let directory: URL
    private let artifact: (SpeechModelArtifact.Model) throws -> SpeechModelArtifact

    public init(directory: URL) {
        self.init(directory: directory, artifact: WhisperModelCatalog.artifact(for:))
    }

    init(directory: URL, artifact: @escaping (SpeechModelArtifact.Model) throws -> SpeechModelArtifact) {
        self.directory = directory
        self.artifact = artifact
    }

    public func install(
        stagedFile: URL,
        for model: SpeechModelArtifact.Model,
        isCancelled: () -> Bool = { false }
    ) throws {
        if isCancelled() { throw CancellationError() }
        let source = try SpeechModelStagedFileValidator.openStagedFile(at: stagedFile)
        defer { close(source) }
        try install(stagedDescriptor: source, for: model, isCancelled: isCancelled)
    }

    func install(stagedDescriptor source: Int32, for model: SpeechModelArtifact.Model, isCancelled: () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
        let trustedArtifact = try artifact(model)
        try withCacheDirectory(create: true, lock: LOCK_EX, ifMissing: (), isCancelled: isCancelled) { cache in
            try Self.unlink(Self.installationName, from: cache)
            let staged = openat(cache, Self.installationName, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard staged >= 0 else { throw Self.fileError() }
            defer { close(staged) }
            var activated = false
            defer {
                if !activated {
                    unlinkat(cache, Self.installationName, 0)
                }
            }

            try SpeechModelStagedFileValidator.validate(source, against: trustedArtifact, isCancelled: isCancelled) { chunk in
                try Self.write(chunk, to: staged)
            }
            guard fchmod(staged, 0o400) == 0 else { throw Self.fileError() }
            while fsync(staged) != 0 {
                guard errno == EINTR else { throw Self.fileError() }
                if isCancelled() { throw CancellationError() }
            }
            if isCancelled() { throw CancellationError() }
            guard renameat(cache, Self.installationName, cache, Self.fileName(for: model)) == 0 else {
                throw Self.fileError()
            }
            activated = true
        }
    }

    public func withInstalledModel<Result>(
        _ model: SpeechModelArtifact.Model,
        isCancelled: () -> Bool = { false },
        read: (FileHandle) throws -> Result
    ) throws -> Result? {
        let trustedArtifact = try artifact(model)
        return try withCacheDirectory(create: false, lock: LOCK_SH, ifMissing: nil, isCancelled: isCancelled) { cache in
            let file = openat(cache, Self.fileName(for: model), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            if file < 0 {
                if errno == ENOENT { return nil }
                if errno == ELOOP { throw SpeechModelStagedFileError.invalidStagedFile }
                throw Self.fileError()
            }
            let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
            defer { try? handle.close() }
            try SpeechModelStagedFileValidator.validate(file, against: trustedArtifact, isCancelled: isCancelled)
            guard lseek(file, 0, SEEK_SET) == 0 else { throw Self.fileError() }
            if isCancelled() { throw CancellationError() }
            return try read(handle)
        }
    }

    public func remove(_ model: SpeechModelArtifact.Model, isCancelled: () -> Bool = { false }) throws {
        try withCacheDirectory(create: false, lock: LOCK_EX, ifMissing: (), isCancelled: isCancelled) { cache in
            try Self.unlink(Self.installationName, from: cache)
            if isCancelled() { throw CancellationError() }
            try Self.unlink(Self.fileName(for: model), from: cache)
        }
    }

    private func withCacheDirectory<Result>(
        create: Bool, lock: Int32, ifMissing: Result, isCancelled: () -> Bool, _ access: (Int32) throws -> Result
    ) throws -> Result {
        if isCancelled() { throw CancellationError() }
        guard directory.isFileURL else { throw WhisperModelCacheError.invalidCacheDirectory }
        let cache = try directory.withUnsafeFileSystemRepresentation { path -> Int32? in
            guard let path else { throw WhisperModelCacheError.invalidCacheDirectory }
            if create, mkdir(path, 0o700) != 0, errno != EEXIST { throw Self.fileError() }
            let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            if descriptor < 0 {
                if !create, errno == ENOENT { return nil }
                if errno == ENOTDIR || errno == ELOOP { throw WhisperModelCacheError.invalidCacheDirectory }
                throw Self.fileError()
            }
            return descriptor
        }
        guard let cache else { return ifMissing }
        defer { close(cache) }

        var metadata = stat()
        guard fstat(cache, &metadata) == 0 else { throw Self.fileError() }
        guard metadata.st_uid == geteuid(), metadata.st_mode & 0o077 == 0 else {
            throw WhisperModelCacheError.invalidCacheDirectory
        }
        while flock(cache, lock | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else { throw Self.fileError(code) }
            if isCancelled() { throw CancellationError() }
            if code == EWOULDBLOCK { Thread.sleep(forTimeInterval: 0.01) }
        }
        if isCancelled() { throw CancellationError() }
        return try access(cache)
    }

    private static func fileName(for model: SpeechModelArtifact.Model) -> String {
        "\(model.rawValue).bin"
    }

    private static func unlink(_ name: String, from directory: Int32) throws {
        if unlinkat(directory, name, 0) != 0, errno != ENOENT {
            throw fileError()
        }
    }

    private static func write(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
            if count > 0 {
                offset += count
            } else if count == 0 || errno != EINTR {
                throw count == 0 ? POSIXError(.EIO) : fileError()
            }
        }
    }

    private static func fileError(_ code: Int32 = errno) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
