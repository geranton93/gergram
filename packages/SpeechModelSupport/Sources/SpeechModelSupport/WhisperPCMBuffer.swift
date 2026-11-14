import AVFoundation
import CoreMedia

public final class WhisperPCMBuffer {
    public enum Failure: Error, Equatable {
        case invalidFormat
        case invalidFrame
        case tooLong
        case empty
        case cancelled
        case conversionFailed
    }

    public static let sampleRate = 16_000
    public static let maximumSamples = 60 * sampleRate
    private static let sourceRate = 48_000
    private static let maximumPacketFrames = sourceRate
    private static let downsampleRatio = sourceRate / sampleRate
    private static let inputCapacity: AVAudioFrameCount = 4096
    private static let outputCapacity: AVAudioFrameCount = 1024

    private let converter: AVAudioConverter
    private let monoInput: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private var pcmInput: AVAudioPCMBuffer?
    private var inputFrames = 0
    private var samples: [Float] = []
    private var isFinished = false

    public init() throws {
        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(Self.sourceRate), channels: 1),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(Self.sampleRate), channels: 1),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let monoInput = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.inputCapacity),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: Self.outputCapacity) else {
            throw Failure.conversionFailed
        }
        self.converter = converter
        self.monoInput = monoInput
        self.output = output
    }

    public func append(_ source: CMSampleBuffer, isCancelled: () -> Bool = { false }) throws {
        guard !isFinished else { throw Failure.invalidFrame }
        if isCancelled() { throw Failure.cancelled }
        let frames = CMSampleBufferGetNumSamples(source)
        guard CMSampleBufferIsValid(source), CMSampleBufferDataIsReady(source),
              (1...Self.maximumPacketFrames).contains(frames) else { throw Failure.invalidFrame }
        guard let description = CMSampleBufferGetFormatDescription(source),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM, format.mSampleRate == Double(Self.sourceRate),
              (1...2).contains(format.mChannelsPerFrame), format.mFramesPerPacket == 1,
              format.mBitsPerChannel == 16, format.mBytesPerFrame == 2 * format.mChannelsPerFrame,
              format.mBytesPerPacket == format.mBytesPerFrame,
              format.mFormatFlags & ~kAudioFormatFlagIsNonMixable ==
                (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked) else {
            throw Failure.invalidFormat
        }
        guard frames <= 60 * Self.sourceRate - inputFrames else { throw Failure.tooLong }

        let channels = Int(format.mChannelsPerFrame)
        if pcmInput?.format.channelCount != format.mChannelsPerFrame {
            guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(Self.sourceRate),
                                                  channels: format.mChannelsPerFrame, interleaved: true),
                  let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.inputCapacity) else {
                throw Failure.conversionFailed
            }
            pcmInput = input
        }
        guard let pcmInput, let pcm = pcmInput.int16ChannelData?[0],
              let mono = monoInput.floatChannelData?[0] else { throw Failure.conversionFailed }

        var offset = 0
        var inputFailure: Failure?
        do {
            try convert(isCancelled: isCancelled, draining: false, sampleLimit: Self.maximumSamples) { requested, status in
                if isCancelled() {
                    inputFailure = .cancelled
                } else if offset < frames, requested > 0 {
                    let count = min(Int(requested), Int(Self.inputCapacity), frames - offset)
                    pcmInput.frameLength = AVAudioFrameCount(count)
                    let copy = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                        source, at: Int32(offset), frameCount: Int32(count), into: pcmInput.mutableAudioBufferList
                    )
                    if copy == noErr {
                        for index in 0..<count {
                            let sample = Float(pcm[index * channels])
                            mono[index] = channels == 1 ? sample / 32768 : (sample + Float(pcm[index * channels + 1])) / 65536
                        }
                        monoInput.frameLength = AVAudioFrameCount(count)
                        offset += count
                        status.pointee = .haveData
                        return monoInput
                    }
                    inputFailure = .invalidFrame
                }
                status.pointee = .noDataNow
                return nil
            }
            if let inputFailure { throw inputFailure }
            guard offset == frames else { throw Failure.conversionFailed }
            inputFrames += frames
        } catch {
            isFinished = true
            samples.removeAll()
            throw inputFailure ?? error
        }
    }

    public func finish(isCancelled: () -> Bool = { false }) throws -> [Float] {
        guard !isFinished else { throw Failure.invalidFrame }
        isFinished = true
        defer { samples.removeAll() }
        if isCancelled() { throw Failure.cancelled }
        guard inputFrames > 0 else { throw Failure.empty }
        let expectedSamples = inputFrames / Self.downsampleRatio
        guard expectedSamples > 0 else { throw Failure.empty }
        try convert(isCancelled: isCancelled, draining: true, sampleLimit: expectedSamples) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        guard samples.count == expectedSamples else { throw Failure.conversionFailed }
        return samples
    }

    private func convert(
        isCancelled: () -> Bool, draining: Bool, sampleLimit: Int,
        input: AVAudioConverterInputBlock
    ) throws {
        while true {
            if isCancelled() { throw Failure.cancelled }
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            guard error == nil, status != .error, let channel = output.floatChannelData?[0] else {
                throw Failure.conversionFailed
            }
            let count = Int(output.frameLength)
            let remaining = sampleLimit - samples.count
            guard remaining >= 0, draining || count <= remaining else { throw Failure.tooLong }
            let values = UnsafeBufferPointer(start: channel, count: min(count, remaining))
            guard values.allSatisfy(\.isFinite) else { throw Failure.conversionFailed }
            samples.append(contentsOf: values)
            switch status {
            case .haveData:
                guard count > 0 else { throw Failure.conversionFailed }
            case .inputRanDry:
                guard !draining else { throw Failure.conversionFailed }
                return
            case .endOfStream:
                guard draining else { throw Failure.conversionFailed }
                return
            case .error:
                throw Failure.conversionFailed
            @unknown default:
                throw Failure.conversionFailed
            }
        }
    }
}
