import AppKit
import AVFoundation
import CoreMedia
import Foundation
import InAppSettings
import Speech
import SwiftSignalKit
import TelegramMediaPlayer
import TGUIKit
import XCTest
@testable import ChatUI

final class ChatReceivedAudioTranscriptionTests: XCTestCase {
    @MainActor
    func testWindowVisibilityLossEndsTranscriptSheet() {
        let window = makeTranscriptWindow()
        let sheet = makeTranscriptWindow()
        let action = ChatReceivedAudioTranscriptionAction()
        _ = action.beginWindowLifetime(window.visibility)
        window.beginSheet(sheet, completionHandler: action.trackTranscriptSheet(sheet))
        XCTAssertTrue(sheet.sheetParent === window)

        window.orderOut(nil)

        XCTAssertNil(sheet.sheetParent)
    }

    @MainActor
    func testDismissingTranscriptSheetDisposesWindowObservation() {
        let window = makeTranscriptWindow()
        let sheet = makeTranscriptWindow()
        let disposed = expectation(description: "Window visibility observation disposed")
        let action = ChatReceivedAudioTranscriptionAction()
        _ = action.beginWindowLifetime(Signal { _ in ActionDisposable { disposed.fulfill() } })
        window.beginSheet(sheet, completionHandler: action.trackTranscriptSheet(sheet))

        window.endSheet(sheet)

        wait(for: [disposed], timeout: 1)
        withExtendedLifetime(action) {}
    }

    @MainActor
    func testReleasingActionEndsTranscriptSheetAndDisposesWindowObservation() throws {
        let window = makeTranscriptWindow()
        let sheet = makeTranscriptWindow()
        let disposed = expectation(description: "Window visibility observation disposed")
        var action: ChatReceivedAudioTranscriptionAction? = ChatReceivedAudioTranscriptionAction()
        _ = action?.beginWindowLifetime(Signal { _ in ActionDisposable { disposed.fulfill() } })
        window.beginSheet(sheet, completionHandler: try XCTUnwrap(action).trackTranscriptSheet(sheet))
        XCTAssertTrue(sheet.sheetParent === window)
        let trackedAction = { [weak action] in action }

        action = nil

        XCTAssertNil(trackedAction())
        XCTAssertNil(sheet.sheetParent)
        wait(for: [disposed], timeout: 1)
    }

    func testSpeechRequestRequiresSupportedOnDeviceRecognition() throws {
        guard #available(macOS 10.15, *) else { return }
        XCTAssertNil(ChatReceivedAudioTranscription.makeRequest(supportsOnDeviceRecognition: false))
        let request = try XCTUnwrap(ChatReceivedAudioTranscription.makeRequest(supportsOnDeviceRecognition: true))
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertFalse(request.shouldReportPartialResults)
    }

    func testExplicitLocaleOverridesComposerAndRequiresExactSupportedRegion() {
        let languages = ["en_US", "en_GB", "pt_PT", "pt_BR", "zh_TW", "zh_CN"]
        func candidates(_ identifier: String) -> [String] {
            ChatReceivedAudioTranscription.languageCandidates(selection: .locale(identifier),
                composerLanguage: "en-US", preferredLanguages: ["en-US", "pt-PT"], supported: languages)
        }
        XCTAssertEqual(candidates("pt-br"), ["pt_BR"])
        XCTAssertEqual(candidates("zh-tw"), ["zh_TW"])
        XCTAssertEqual(candidates("en-GB"), ["en_GB"])
        XCTAssertEqual(candidates("en-CA"), [])
        XCTAssertEqual(candidates("en"), [])
        XCTAssertEqual(candidates("qzz-ZZ"), [])
    }

    func testAutomaticPreservesComposerAndSystemLanguageResolution() {
        let supported = ["en_US", "en_GB", "de_DE", "pt_BR", "fr_FR", "it_IT"]
        let preferred = ["en-GB", "en-US", "de-AT", "pt-PT", "fr-CA", "it-IT"]
        func automatic(composer: String?) -> [String] {
            ChatReceivedAudioTranscription.languageCandidates(selection: .automatic, composerLanguage: composer,
                preferredLanguages: preferred, supported: supported)
        }
        XCTAssertEqual(automatic(composer: "en"), ["en_GB"])
        XCTAssertEqual(automatic(composer: "pt-PT"), ["pt_BR"])
        XCTAssertEqual(automatic(composer: "qzz-ZZ"), [])
        XCTAssertEqual(automatic(composer: nil), ["en_GB", "de_DE", "pt_BR", "fr_FR"])
    }

    func testLanguagePreferencePersistsUnsupportedChoiceAndResetsToAutomatic() throws {
        let suite = "gergram-received-transcription-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReceivedAudioTranscriptionLanguagePreferences(defaults: defaults)
        var selections: [ReceivedAudioTranscriptionLanguagePreferences.Selection] = []
        let disposable = preferences.signal.start(next: { selections.append($0) })
        defer { disposable.dispose() }

        XCTAssertEqual(preferences.selection, .automatic)
        let unavailable = "qzz_ZZ"
        preferences.setSelection(.locale(unavailable))
        preferences.setSelection(.locale(unavailable))
        let stored = ReceivedAudioTranscriptionLanguagePreferences(defaults: defaults).selection
        XCTAssertEqual(stored, .locale(unavailable))
        preferences.setSelection(.automatic)
        XCTAssertEqual(ReceivedAudioTranscriptionLanguagePreferences(defaults: defaults).selection, .automatic)
        XCTAssertEqual(selections, [.automatic, stored, .automatic])
    }

    func testAppleLanguageDiscoveryChecksActualOnDeviceLocaleWithoutAuthorization() async {
        guard #available(macOS 10.15, *) else { return }
        let authorization = SFSpeechRecognizer.authorizationStatus()
        let discovered: [Locale] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ReceivedAudioTranscriptionLanguagePreferences.availableLocales())
            }
        }
        let supported = SFSpeechRecognizer.supportedLocales()
        for locale in discovered {
            XCTAssertTrue(supported.contains(locale))
            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                XCTFail("Recognizer no longer supports \(locale.identifier)")
                continue
            }
            XCTAssertTrue(recognizer.supportsOnDeviceRecognition)
            XCTAssertTrue(ReceivedAudioTranscriptionLanguagePreferences.localeIdentifierMatches(recognizer.locale.identifier, locale.identifier))
        }
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), authorization)
        XCTAssertNil(ChatReceivedAudioTranscription.recognizer(selection: .locale("qzz_ZZ"),
            composerLanguage: "en-US", preferredLanguages: ["en-US"]))
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

    @MainActor
    private func makeTranscriptWindow() -> Window {
        _ = NSApplication.shared
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }
}
