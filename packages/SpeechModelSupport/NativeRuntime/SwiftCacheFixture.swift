import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
@testable import SpeechModelSupport

private enum FixtureError: Error {
    case unexpectedResult
}

private func makeSilence() throws -> CMSampleBuffer {
    let frames = 48_000
    let byteCount = frames * MemoryLayout<Int16>.size
    var format = AudioStreamBasicDescription(mSampleRate: Double(frames), mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var formatDescription: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription) == noErr,
        let formatDescription else { throw FixtureError.unexpectedResult }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
        blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
        dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
        let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0,
            dataLength: byteCount) == noErr else { throw FixtureError.unexpectedResult }
    var buffer: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block,
        formatDescription: formatDescription, sampleCount: frames, presentationTimeStamp: .zero,
        packetDescriptions: nil, sampleBufferOut: &buffer) == noErr,
        let buffer else { throw FixtureError.unexpectedResult }
    return buffer
}

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let bytes = try Data(contentsOf: source)
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }

let revision = "d1be6fde11ac6e0407606b4e42fe72d34add8037"
let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
let cache = WhisperModelCache(directory: root.appendingPathComponent("models")) { model in
    try SpeechModelArtifact(
        manifestVersion: 1, model: model, format: .whisperCppGGML, architecture: .universal, license: .mit,
        sourceURL: URL(string: "https://example.invalid/\(revision)/fixture.bin")!, sourceRevision: revision,
        byteCount: Int64(bytes.count), sha256: digest
    )
}

let converter = try WhisperPCMBuffer()
try converter.append(makeSilence())
let samples = try converter.finish()
guard samples.count == 16_000, samples.allSatisfy({ $0 == 0 }) else { throw FixtureError.unexpectedResult }

func expect(_ expected: WhisperNativeTranscription.Failure, _ recognize: () throws -> String) throws {
    do {
        _ = try recognize()
        throw FixtureError.unexpectedResult
    } catch let actual as WhisperNativeTranscription.Failure {
        guard actual == expected else { throw actual }
    }
}

try expect(.modelUnavailable) {
    try WhisperNativeTranscription.recognize(samples: samples, language: "en", model: .whisperTiny, cache: cache)
}
try cache.install(stagedFile: source, for: .whisperTiny)

var checks = 0
try expect(.noSpeech) {
    try WhisperNativeTranscription.recognize(samples: samples, language: "en", model: .whisperTiny, cache: cache) {
        checks += 1
        return false
    }
}
guard checks > 4 else { throw FixtureError.unexpectedResult }
let cancelCheck = checks - 2
checks = 0
try expect(.cancelled) {
    try WhisperNativeTranscription.recognize(samples: samples, language: "en", model: .whisperTiny, cache: cache) {
        checks += 1
        return checks >= cancelCheck
    }
}
guard checks == cancelCheck else { throw FixtureError.unexpectedResult }
try expect(.invalidInput) {
    try WhisperNativeTranscription.recognize(samples: samples, language: "unknown-language", model: .whisperTiny, cache: cache)
}
