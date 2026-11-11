import Foundation

public enum Configuration : String {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }
    case source = "SOURCE"
    case apiId = "GergramAPIID"
    case apiHash = "GergramAPIHash"
    case bundleId = "GergramBundleID"
    case crashReportBot = "GergramCrashReportBot"
    case teamId = "GergramTeamID"
    
    public static func value(for key: Configuration) -> String? {
        guard let value = Bundle.main.infoDictionary?[key.rawValue] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), !trimmed.hasPrefix("${") else {
            return nil
        }
        return trimmed
    }
}
