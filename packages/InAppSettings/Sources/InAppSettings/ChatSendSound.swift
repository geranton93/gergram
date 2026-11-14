import Foundation

public enum ChatSendSound: Equatable {
    case automatic
    case silent
    case audible

    public var notificationIsSilent: Bool? {
        switch self {
        case .automatic: return nil
        case .silent: return true
        case .audible: return false
        }
    }

    public func resolving(defaultIsSilent: Bool) -> Self {
        guard self == .automatic else { return self }
        return defaultIsSilent ? .silent : .audible
    }
}

public enum ChatSendSoundPreferences {
    public static func sendWithoutSoundByDefault(accountId: Int64, defaults: UserDefaults = .standard) -> Bool {
        return defaults.object(forKey: key(accountId)) as? Bool ?? false
    }

    public static func setSendWithoutSoundByDefault(_ value: Bool, accountId: Int64, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key(accountId))
    }

    private static func key(_ accountId: Int64) -> String {
        return "Gergram.Chat.SendWithoutSound.\(accountId)"
    }
}
