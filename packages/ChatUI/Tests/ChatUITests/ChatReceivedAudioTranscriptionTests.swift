import AVFoundation
import CoreMedia
import Foundation
import TelegramMediaPlayer
import XCTest
@testable import ChatUI

final class ChatReceivedAudioTranscriptionTests: XCTestCase {
    func testSpeechRequestRequiresSupportedOnDeviceRecognition() throws {
        guard #available(macOS 10.15, *) else { return }
        XCTAssertNil(ChatReceivedAudioTranscription.makeRequest(supportsOnDeviceRecognition: false))
        let request = try XCTUnwrap(ChatReceivedAudioTranscription.makeRequest(supportsOnDeviceRecognition: true))
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertFalse(request.shouldReportPartialResults)
    }

    func testMetadataLimitsRejectUnknownAndOversizedFiles() throws {
        XCTAssertNoThrow(try ChatReceivedAudioTranscription.validateMetadata(size: 24_000_000, duration: 60))
        XCTAssertNoThrow(try ChatReceivedAudioTranscription.validateMetadata(size: 1, duration: nil))
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.validateMetadata(size: 24_000_001, duration: 1)) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .tooLong)
        }
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.validateMetadata(size: nil, duration: 1)) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .mediaUnavailable)
        }
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.validateMetadata(size: 1, duration: .nan)) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .mediaUnavailable)
        }
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.validateMetadata(size: 1, duration: 60.01)) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .tooLong)
        }
    }

    func testDecodedFrameLimitStopsBeforeAppendingOverBudget() throws {
        let full = try frame(samples: 48_000)
        let extra = try frame(samples: 1)
        var reads = 0
        var appended = 0
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.streamFrames(next: {
            reads += 1
            return .frame(reads <= 60 ? full : extra)
        }, isCancelled: { false }, append: { _ in
            appended += 1
        })) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .tooLong)
        }
        XCTAssertEqual(reads, 61)
        XCTAssertEqual(appended, 60)
    }

    func testCancellationWhileReaderIsDecodingDropsTheReturnedFrame() throws {
        let audio = try frame(samples: 960)
        var cancelled = false
        var appended = 0
        XCTAssertThrowsError(try ChatReceivedAudioTranscription.streamFrames(next: {
            cancelled = true
            return .frame(audio)
        }, isCancelled: { cancelled }, append: { _ in appended += 1 })) {
            XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .cancelled)
        }
        XCTAssertEqual(appended, 0)
    }

    func testEmptyAndWaitingReadersFailInsteadOfProducingATranscript() throws {
        for result: FFMpegFileReader.ReadFrameResult in [.endOfStream, .waitingForMoreData, .error] {
            XCTAssertThrowsError(try ChatReceivedAudioTranscription.streamFrames(next: { result }, isCancelled: { false }, append: { _ in
                XCTFail("Empty source appended an audio buffer")
            })) {
                XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .mediaUnavailable)
            }
        }
    }

    func testAudioBudgetRejectsWrongSampleRateAndOversizedFrame() throws {
        var budget = ChatReceivedAudioTranscription.AudioBudget()
        for audio in [try frame(samples: 960, sampleRate: 44_100), try frame(samples: 48_001)] {
            XCTAssertThrowsError(try budget.consume(audio.sampleBuffer)) {
                XCTAssertEqual($0 as? ChatReceivedAudioTranscription.Failure, .mediaUnavailable)
            }
        }
        XCTAssertEqual(budget.samples, 0)
    }

    func testDecodesLocalVoiceAndRoundVideoSamples() throws {
        guard let directory = ProcessInfo.processInfo.environment["GERGRAM_RECEIVED_AUDIO_FIXTURES"] else {
            throw XCTSkip("Set GERGRAM_RECEIVED_AUDIO_FIXTURES to the synthetic fixture directory")
        }
        for name in ["voice.ogg", "round.mp4"] {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            var samples = 0
            try ChatReceivedAudioTranscription.streamAudio(path: path, isCancelled: { false }) {
                samples += CMSampleBufferGetNumSamples($0)
            }
            XCTAssertGreaterThan(samples, 4_800, name)
            XCTAssertLessThan(samples, 48_000, name)
        }
    }

    private func frame(samples: Int, sampleRate: Double = 48_000) throws -> MediaTrackFrame {
        var stream = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &stream, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        let dataLength = samples * Int(stream.mBytesPerFrame)
        var data: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: dataLength,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: dataLength,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &data), noErr)
        var buffer: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: try XCTUnwrap(data),
            formatDescription: try XCTUnwrap(format), sampleCount: samples, presentationTimeStamp: .zero,
            packetDescriptions: nil, sampleBufferOut: &buffer), noErr)
        return MediaTrackFrame(type: .audio, sampleBuffer: try XCTUnwrap(buffer), resetDecoder: false, decoded: true)
    }
}
