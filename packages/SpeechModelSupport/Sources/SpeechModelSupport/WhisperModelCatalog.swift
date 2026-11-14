import Foundation

public enum WhisperModelCatalog {
    private static let sourceRevision = "80da2d8bfee42b0e836fc3a9890373e5defc00a6"

    public static func artifact(for model: SpeechModelArtifact.Model) throws -> SpeechModelArtifact {
        switch model {
        case .whisperTiny:
            return try artifact(
                model: model, fileName: "ggml-tiny.bin", byteCount: 77_691_713,
                sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
            )
        case .whisperBase:
            return try artifact(
                model: model, fileName: "ggml-base.bin", byteCount: 147_951_465,
                sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
            )
        case .whisperSmall:
            return try artifact(
                model: model, fileName: "ggml-small.bin", byteCount: 487_601_967,
                sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
            )
        }
    }

    private static func artifact(
        model: SpeechModelArtifact.Model, fileName: String, byteCount: Int64, sha256: String
    ) throws -> SpeechModelArtifact {
        var source = URLComponents()
        source.scheme = "https"
        source.host = "huggingface.co"
        source.path = "/ggerganov/whisper.cpp/resolve/\(sourceRevision)/\(fileName)"
        guard let url = source.url else { throw SpeechModelManifestError.invalidSourceURL }
        return try SpeechModelArtifact(
            manifestVersion: SpeechModelArtifact.currentManifestVersion,
            model: model, format: .whisperCppGGML, architecture: .universal, license: .mit,
            sourceURL: url, sourceRevision: sourceRevision, byteCount: byteCount, sha256: sha256
        )
    }
}
