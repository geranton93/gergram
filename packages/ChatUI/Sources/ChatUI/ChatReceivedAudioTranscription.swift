import AVFoundation
import CoreMedia
import Foundation
import Speech
import SwiftSignalKit
import TelegramMediaPlayer

enum ChatReceivedAudioTranscription {
    enum Failure: Error, Equatable {
        case unavailable
        case denied
        case mediaUnavailable
        case tooLong
        case failed
        case timedOut
        case cancelled
    }

    static let maximumBytes: Int64 = 24_000_000
    static let maximumSeconds: Double = 60
    private static let sampleRate: Double = 48_000
    private static let maximumFrameSamples = 48_000
    private static let maximumChannels: UInt32 = 2

    static func validateMetadata(size: Int64?, duration: Double?) throws {
        guard let size, size > 0 else { throw Failure.mediaUnavailable }
        guard size <= maximumBytes else { throw Failure.tooLong }
        if let duration {
            guard duration.isFinite, duration > 0 else { throw Failure.mediaUnavailable }
            guard duration <= maximumSeconds else { throw Failure.tooLong }
        }
    }

    struct AudioBudget {
        private(set) var samples = 0

        mutating func consume(_ buffer: CMSampleBuffer) throws {
            let frames = CMSampleBufferGetNumSamples(buffer)
            guard frames > 0, frames <= maximumFrameSamples,
                  CMSampleBufferDataIsReady(buffer),
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  let audio = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  audio.mFormatID == kAudioFormatLinearPCM,
                  audio.mSampleRate == sampleRate,
                  audio.mChannelsPerFrame > 0, audio.mChannelsPerFrame <= maximumChannels else {
                throw Failure.mediaUnavailable
            }
            let updated = samples + frames
            guard updated <= Int(maximumSeconds * sampleRate) else { throw Failure.tooLong }
            samples = updated
        }
    }

    @available(macOS 10.15, *)
    static func recognizer(selection: String?, preferredLanguages: [String]) -> SFSpeechRecognizer? {
        let supported = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        let candidates: [String]
        if let selection {
            candidates = ChatInputDictationText.resolveLanguage([selection], preferred: preferredLanguages, supported: supported).map { [$0] } ?? []
        } else {
            candidates = ChatInputDictationText.automaticLocales(preferred: preferredLanguages, supported: supported, limit: 4)
        }
        for identifier in candidates {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
               recognizer.supportsOnDeviceRecognition, recognizer.isAvailable {
                return recognizer
            }
        }
        return nil
    }

    @available(macOS 10.15, *)
    static func makeRequest(supportsOnDeviceRecognition: Bool) -> SFSpeechAudioBufferRecognitionRequest? {
        guard supportsOnDeviceRecognition else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        return request
    }

    @available(macOS 10.15, *)
    static func recognize(path: String, using recognizer: SFSpeechRecognizer) -> Signal<String, Failure> {
        return Signal { subscriber in
            guard recognizer.isAvailable,
                  let request = makeRequest(supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition) else {
                subscriber.putError(.unavailable)
                return EmptyDisposable
            }
            let operation = Operation(request: request, subscriber: subscriber)
            operation.start(path: path, recognizer: recognizer)
            return ActionDisposable { operation.cancel() }
        } |> runOn(Queue.mainQueue())
    }

    @available(macOS 10.15, *)
    private final class Operation {
        private static let decodeQueue = Queue(name: "GergramReceivedAudioTranscription")

        private let request: SFSpeechAudioBufferRecognitionRequest
        private let subscriber: Subscriber<String, Failure>
        private let terminal = Atomic(value: false)
        private var didFeedAudio = false
        private var finalTranscript: String?
        private var task: SFSpeechRecognitionTask?

        init(request: SFSpeechAudioBufferRecognitionRequest, subscriber: Subscriber<String, Failure>) {
            self.request = request
            self.subscriber = subscriber
        }

        func start(path: String, recognizer: SFSpeechRecognizer) {
            recognizer.queue = .main
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.finalTranscript = text
                    self.finishIfReady()
                } else if error != nil {
                    self.finish(.failure(.failed))
                }
            }
            Self.decodeQueue.async { [weak self] in
                guard let self else { return }
                do {
                    try streamAudio(path: path, isCancelled: { self.terminal.with { $0 } }) { self.request.appendAudioSampleBuffer($0) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.terminal.with({ $0 }) else { return }
                        self.didFeedAudio = true
                        self.request.endAudio()
                        self.finishIfReady()
                    }
                } catch {
                    let failure = error as? Failure ?? .mediaUnavailable
                    DispatchQueue.main.async { [weak self] in
                        self?.finish(.failure(failure))
                    }
                }
            }
        }

        private func finishIfReady() {
            guard didFeedAudio, let finalTranscript else { return }
            finish(finalTranscript.isEmpty ? .failure(.failed) : .success(finalTranscript))
        }

        private func finish(_ result: Result<String, Failure>) {
            guard !terminal.swap(true) else { return }
            task?.cancel()
            task = nil
            switch result {
            case let .success(text):
                subscriber.putNext(text)
                subscriber.putCompletion()
            case let .failure(error):
                subscriber.putError(error)
            }
        }

        func cancel() {
            guard !terminal.swap(true) else { return }
            DispatchQueue.main.async {
                self.task?.cancel()
                self.task = nil
            }
        }
    }

    static func streamAudio(path: String, isCancelled: () -> Bool, append: (CMSampleBuffer) -> Void) throws {
        guard !isCancelled() else { throw Failure.cancelled }
        let source = URL(fileURLWithPath: path)
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false else { throw Failure.mediaUnavailable }
        try validateMetadata(size: values.fileSize.map(Int64.init), duration: nil)
        guard let reader = FFMpegFileReader(source: .file(path), useHardwareAcceleration: false, selectedStream: .mediaType(.audio), seek: nil, maxReadablePts: nil) else {
            throw Failure.mediaUnavailable
        }
        let duration = CMTimeGetSeconds(reader.duration())
        guard !(duration.isFinite && duration > maximumSeconds) else { throw Failure.tooLong }
        try streamFrames(next: { reader.readFrame() }, isCancelled: isCancelled, append: append)
    }

    static func streamFrames(next: () -> FFMpegFileReader.ReadFrameResult, isCancelled: () -> Bool, append: (CMSampleBuffer) -> Void) throws {
        var budget = AudioBudget()
        while !isCancelled() {
            switch next() {
            case let .frame(frame):
                let sampleBuffer = frame.sampleBuffer
                try budget.consume(sampleBuffer)
                guard !isCancelled() else { throw Failure.cancelled }
                append(sampleBuffer)
            case .endOfStream:
                guard budget.samples > 0 else { throw Failure.mediaUnavailable }
                return
            case .waitingForMoreData, .error:
                throw Failure.mediaUnavailable
            }
        }
        throw Failure.cancelled
    }
}
