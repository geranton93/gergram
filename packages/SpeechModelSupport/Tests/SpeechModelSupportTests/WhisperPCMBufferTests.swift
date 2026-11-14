import AVFoundation
import CoreMedia
import XCTest
@testable import SpeechModelSupport

final class WhisperPCMBufferTests: XCTestCase {
    func testMonoConversionPreservesToneAndDrainsExactly() throws {
        let frames = 48_000
        let source = (0..<frames).map { Int16(16_384 * sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        let buffer = try WhisperPCMBuffer()
        try buffer.append(makeFrame(source))
        let samples = try buffer.finish()
        XCTAssertEqual(samples.count, 16_000)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertEqual(peak(samples), 0.5, accuracy: 0.012)
        let steadyState = samples.dropFirst(100).dropLast(100)
        let ascendingCrossings = zip(steadyState.dropLast(), steadyState.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        XCTAssertEqual(Double(ascendingCrossings), 440 * Double(steadyState.count) / 16_000, accuracy: 2)
    }

    func testStereoDownmixAveragesBothChannelsAndRetainsConverterAcrossFrames() throws {
        let reference = try WhisperPCMBuffer()
        let mixed = try WhisperPCMBuffer()
        for size in [4095, 473, 5377, 4004, 4051] {
            try reference.append(makeFrame([Int16](repeating: 8192, count: size)))
            try mixed.append(makeFrame((0..<size).flatMap { _ in [Int16(24576), -8192] }, channels: 2))
        }
        let expected = try reference.finish()
        let actual = try mixed.finish()
        XCTAssertEqual(actual.count, 6000)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual[5900], 0.25, accuracy: 0.003)
    }

    func testChangingFromStereoToMonoAndIrregularPacketEdgesDoesNotLoseFrames() throws {
        let sampleCount = 12_000
        let reference = try WhisperPCMBuffer()
        try reference.append(makeFrame([Int16](repeating: 4096, count: sampleCount)))
        let expected = try reference.finish()

        let split = try WhisperPCMBuffer()
        try split.append(makeFrame((0..<5001).flatMap { _ in [Int16(12288), -4096] }, channels: 2))
        try split.append(makeFrame([Int16](repeating: 4096, count: sampleCount - 5001)))
        let actual = try split.finish()
        XCTAssertEqual(actual.count, expected.count)
        let error = zip(actual, expected).map { abs($0 - $1) }.max()
        XCTAssertLessThanOrEqual(try XCTUnwrap(error), 0.00002)
    }

    func testDurationLimitBindsSourceAndOutput() throws {
        let converter = try WhisperPCMBuffer()
        let block = try makeFrame([Int16](repeating: 0, count: 48_000))
        for _ in 0..<60 {
            try converter.append(block)
        }
        XCTAssertThrowsError(try converter.append(makeFrame([0]))) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .tooLong)
        }
        XCTAssertEqual(try converter.finish().count, WhisperPCMBuffer.maximumSamples)
    }

    func testRejectsIncompatibleAndInvalidFramesAndCancellation() throws {
        let converter = try WhisperPCMBuffer()
        XCTAssertThrowsError(try converter.append(makeFrame([0], rate: 44_100))) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .invalidFormat)
        }
        let invalid = try makeFrame([0])
        CMSampleBufferInvalidate(invalid)
        XCTAssertThrowsError(try converter.append(invalid)) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .invalidFrame)
        }
        XCTAssertThrowsError(try converter.append(makeFrame([0]), isCancelled: { true })) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .cancelled)
        }
        XCTAssertThrowsError(try converter.finish()) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .empty)
        }

        let active = try WhisperPCMBuffer()
        var checks = 0
        let block = try makeFrame([Int16](repeating: .min, count: 48_000))
        XCTAssertThrowsError(try active.append(block, isCancelled: { checks += 1; return checks > 4 })) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .cancelled)
        }
        XCTAssertThrowsError(try active.finish()) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .invalidFrame)
        }
    }

    func testExtremesAreFiniteAndFinishCanCancel() throws {
        let block = try makeFrame((0..<12_000).flatMap { _ in [Int16.min, Int16.max] }, channels: 2)
        let converter = try WhisperPCMBuffer()
        try converter.append(block)
        let output = try converter.finish()
        XCTAssertTrue(output.allSatisfy(\.isFinite))
        XCTAssertLessThan(peak(output), 0.0001)

        let cancelled = try WhisperPCMBuffer()
        try cancelled.append(block)
        XCTAssertThrowsError(try cancelled.finish(isCancelled: { true })) {
            XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .cancelled)
        }
    }

    func testShortAndFractionalPacketDurationsDoNotInventOutputSamples() throws {
        for count in [1, 2, 3, 4, 5, 12, 1025] {
            let converter = try WhisperPCMBuffer()
            try converter.append(makeFrame([Int16](repeating: 10, count: count)))
            if count < 3 {
                XCTAssertThrowsError(try converter.finish()) {
                    XCTAssertEqual($0 as? WhisperPCMBuffer.Failure, .empty)
                }
            } else {
                XCTAssertEqual(try converter.finish().count, count / 3)
            }
        }
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    private func makeFrame(_ input: [Int16], channels: UInt32 = 1, rate: Double = 48_000) throws -> CMSampleBuffer {
        let frameCount = input.count / Int(channels)
        let frameBytes = channels * UInt32(MemoryLayout<Int16>.size)
        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: frameBytes, mFramesPerPacket: 1, mBytesPerFrame: frameBytes,
            mChannelsPerFrame: channels, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description), noErr)
        let dataBytes = input.count * MemoryLayout<Int16>.stride
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: dataBytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: dataBytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block), noErr)
        let storage = try XCTUnwrap(block)
        try input.withUnsafeBytes { bytes in
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: try XCTUnwrap(bytes.baseAddress), blockBuffer: storage,
                offsetIntoDestination: 0, dataLength: dataBytes), noErr)
        }
        var frame: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: storage,
            formatDescription: try XCTUnwrap(description), sampleCount: frameCount, presentationTimeStamp: .zero,
            packetDescriptions: nil, sampleBufferOut: &frame), noErr)
        return try XCTUnwrap(frame)
    }
}
