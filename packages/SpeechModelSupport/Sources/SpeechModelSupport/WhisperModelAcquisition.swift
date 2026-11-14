import Darwin
import Foundation

@available(macOS 10.15, *)
public final class WhisperModelAcquisition {
    public typealias Cancel = () -> Void
    public typealias Completion = (Result<Void, Failure>) -> Void

    public enum Failure: Error, Equatable {
        case cancelled
        case busy
        case modelDoesNotMatch
        case fileChanged
        case invalidFile
        case insufficientStorage
        case unableToAccessFile
        case unableToUseCache
    }

    public let cache: WhisperModelCache

    private let queue = DispatchQueue(label: "GergramWhisperModelAcquisition", qos: .userInitiated)
    private let gate = NSLock()
    private var active = false
    private let beginAccess: (URL) -> Bool
    private let endAccess: (URL) -> Void

    public convenience init(appContainer: URL) {
        self.init(
            cache: WhisperModelCache(directory: appContainer.appendingPathComponent("WhisperModels", isDirectory: true)),
            beginAccess: { $0.startAccessingSecurityScopedResource() },
            endAccess: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    init(cache: WhisperModelCache, beginAccess: @escaping (URL) -> Bool, endAccess: @escaping (URL) -> Void) {
        self.cache = cache
        self.beginAccess = beginAccess
        self.endAccess = endAccess
    }

    public func importModel(
        from selectedFile: URL, for model: SpeechModelArtifact.Model, completion: @escaping Completion
    ) -> Cancel {
        perform(completion: completion) { isCancelled in
            guard selectedFile.isFileURL, !selectedFile.hasDirectoryPath else { throw Failure.invalidFile }
            let accessed = self.beginAccess(selectedFile)
            defer { if accessed { self.endAccess(selectedFile) } }

            let descriptor: Int32
            do {
                descriptor = try SpeechModelStagedFileValidator.openStagedFile(at: selectedFile)
            } catch is POSIXError {
                throw Failure.unableToAccessFile
            }
            defer { close(descriptor) }
            try self.cache.install(stagedDescriptor: descriptor, for: model, isCancelled: isCancelled)
        }
    }

    public func removeModel(_ model: SpeechModelArtifact.Model, completion: @escaping Completion) -> Cancel {
        perform(completion: completion) { isCancelled in
            try self.cache.remove(model, isCancelled: isCancelled)
        }
    }

    private func perform(
        completion: @escaping Completion, operation: @escaping (_ isCancelled: () -> Bool) throws -> Void
    ) -> Cancel {
        gate.lock()
        guard !active else {
            gate.unlock()
            DispatchQueue.main.async { completion(.failure(.busy)) }
            return {}
        }
        active = true
        gate.unlock()

        let cancellation = Cancellation()
        queue.async {
            let result: Result<Void, Failure>
            do {
                if cancellation.isCancelled() { throw CancellationError() }
                try operation(cancellation.isCancelled)
                result = .success(())
            } catch {
                result = .failure(Self.failure(for: error))
            }
            self.gate.lock()
            self.active = false
            self.gate.unlock()
            DispatchQueue.main.async { completion(result) }
        }
        return cancellation.cancel
    }

    private static func failure(for error: Error) -> Failure {
        if let failure = error as? Failure { return failure }
        if error is CancellationError { return .cancelled }
        switch error as? SpeechModelStagedFileError {
        case .invalidStagedFile: return .invalidFile
        case .unexpectedSize, .checksumMismatch: return .modelDoesNotMatch
        case .stagedFileChanged: return .fileChanged
        case nil: break
        }
        if let error = error as? POSIXError, error.code == .ENOSPC || error.code == .EDQUOT {
            return .insufficientStorage
        }
        return .unableToUseCache
    }

    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func isCancelled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }
}
