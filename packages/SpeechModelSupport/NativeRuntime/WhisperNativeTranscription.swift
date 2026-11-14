import Foundation
import GergramWhisperRuntime
import SpeechModelSupport

@available(macOS 10.15, *)
public enum WhisperNativeTranscription {
    public enum Failure: Error, Equatable {
        case modelUnavailable
        case invalidInput
        case cancelled
        case modelLoadFailed
        case inferenceFailed
        case noSpeech
        case transcriptTooLong
    }

    private final class Call {
        let isCancelled: () -> Bool
        var transcript: String?

        init(isCancelled: @escaping () -> Bool) {
            self.isCancelled = isCancelled
        }
    }

    public static func recognize(
        samples: [Float], language: String? = nil, model: SpeechModelArtifact.Model,
        cache: WhisperModelCache, isCancelled: @escaping () -> Bool = { false }
    ) throws -> String {
        guard !samples.isEmpty, samples.count <= WhisperPCMBuffer.maximumSamples,
              language?.utf8.contains(0) != true else { throw Failure.invalidInput }
        if isCancelled() { throw Failure.cancelled }

        let transcript: String?
        do {
            transcript = try cache.withInstalledModel(model, isCancelled: isCancelled) { handle in
                try transcribe(samples, language: language ?? "auto", descriptor: handle.fileDescriptor, isCancelled: isCancelled)
            }
        } catch is CancellationError {
            throw Failure.cancelled
        } catch is SpeechModelStagedFileError {
            throw Failure.modelLoadFailed
        }
        guard let transcript else { throw Failure.modelUnavailable }
        return transcript
    }

    private static func transcribe(
        _ samples: [Float], language: String, descriptor: Int32, isCancelled: @escaping () -> Bool
    ) throws -> String {
        let call = Call(isCancelled: isCancelled)
        let status = withExtendedLifetime(call) {
            let context = Unmanaged.passUnretained(call).toOpaque()
            return samples.withUnsafeBufferPointer { samples in
                language.withCString { language in
                    gergramWhisperTranscribe(descriptor, samples.baseAddress, samples.count, language, { context in
                        guard let context else { return true }
                        return Unmanaged<Call>.fromOpaque(context).takeUnretainedValue().isCancelled()
                    }, { text, length, context in
                        guard let text, let context else { return }
                        let bytes = UnsafeRawBufferPointer(start: text, count: length)
                        Unmanaged<Call>.fromOpaque(context).takeUnretainedValue().transcript = String(bytes: bytes, encoding: .utf8)
                    }, context)
                }
            }
        }
        switch status {
        case GergramWhisperOK:
            guard let text = call.transcript else { throw Failure.inferenceFailed }
            let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { throw Failure.noSpeech }
            return transcript
        case GergramWhisperInvalidInput: throw Failure.invalidInput
        case GergramWhisperCancelled: throw Failure.cancelled
        case GergramWhisperModelLoadFailed: throw Failure.modelLoadFailed
        case GergramWhisperNoSpeech: throw Failure.noSpeech
        case GergramWhisperTranscriptTooLong: throw Failure.transcriptTooLong
        default: throw Failure.inferenceFailed
        }
    }
}
