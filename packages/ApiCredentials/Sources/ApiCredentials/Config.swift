import Cocoa

public final class ApiEnvironment {
    public static var apiId: Int32 {
        Configuration.value(for: .apiId).flatMap(Int32.init) ?? 0
    }

    public static var apiHash: String {
        Configuration.value(for: .apiHash) ?? ""
    }

    public static var hasApiCredentials: Bool {
        let hash = apiHash.utf8
        return apiId > 0 && hash.count == 32 && hash.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    public static var bundleId: String {
        Configuration.value(for: .bundleId) ?? ""
    }

    public static var teamId: String {
        Configuration.value(for: .teamId) ?? ""
    }

    private static var applicationGroupURL: URL? {
        let bundleId = self.bundleId
        guard !teamId.isEmpty, !bundleId.isEmpty, !bundleId.lowercased().hasPrefix("ru.keepcoder.telegram"),
              let currentBundleId = Bundle.main.bundleIdentifier,
              currentBundleId == bundleId || currentBundleId == bundleId + ".TelegramShare" else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    public static var containerURL: URL? {
        let containerUrl = applicationGroupURL?.appendingPathComponent(prefix)
        if let containerUrl = containerUrl {
            do {
                try FileManager.default.createDirectory(at: containerUrl, withIntermediateDirectories: true, attributes: nil)
                return containerUrl
            } catch {
                return nil
            }
        }
        return nil
    }
    
    public static func migrate() {
        if let containerURL = containerURL, let legacy = legacyContainerURL, let sequence = FileManager.default.enumerator(atPath: legacy.path) {
            let contents = try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: [])
            if let contents = contents, !contents.isEmpty {
                return
            }
            for value in sequence {
                if let value = value as? String {
                    if !prefixList.contains(value) {
                        try? FileManager.default.moveItem(at: legacy.appendingPathComponent(value), to: containerURL.appendingPathComponent(value))
                    }
                }
            }
        }
    }
    
    public static var legacyContainerURL: URL? {
        applicationGroupURL
    }
    
    public static var group: String {
        return teamId + "." + bundleId
    }
    
    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var prefixList:[String] {
        return ["debug", "stable", "appstore", "beta"]
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
}



