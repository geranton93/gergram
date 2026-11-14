import CryptoKit
import Foundation
import GergramWhisperRuntime
@testable import SpeechModelSupport

private enum FixtureError: Error {
    case unexpectedResult
}

private final class Observation {
    var checks = 0
    var cancelOn = Int.max
    var receivedTranscript = false
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
try cache.install(stagedFile: source, for: .whisperTiny)

private let observation = Observation()
let context = Unmanaged.passUnretained(observation).toOpaque()
let samples = [Float](repeating: 0, count: 16_000)
let result = try cache.withInstalledModel(.whisperTiny) { handle in
    try samples.withUnsafeBufferPointer { samples in
        func check() -> GergramWhisperStatus {
            gergramWhisperTranscribe(handle.fileDescriptor, samples.baseAddress, samples.count, "en", { context in
                guard let context else { return false }
                let observation = Unmanaged<Observation>.fromOpaque(context).takeUnretainedValue()
                observation.checks += 1
                return observation.checks >= observation.cancelOn
            }, { _, _, context in
                guard let context else { return }
                Unmanaged<Observation>.fromOpaque(context).takeUnretainedValue().receivedTranscript = true
            }, context)
        }
        guard check() == GergramWhisperNoSpeech, observation.checks > 3 else { throw FixtureError.unexpectedResult }
        observation.cancelOn = observation.checks - 2
        observation.checks = 0
        guard check() == GergramWhisperCancelled, !observation.receivedTranscript,
              try handle.offset() == 0 else { throw FixtureError.unexpectedResult }
        return true
    }
}
guard result == true else { throw FixtureError.unexpectedResult }
