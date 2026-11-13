import Foundation

public struct MessageContextMenuPreferences {
    public enum Visibility: String, CaseIterable {
        case shown
        case hidden
        case extended
    }

    public enum Action: String, CaseIterable {
        case reactionsPanel
        case viewsPanel
        case hideMessage
        case senderSearch
        case messageDetails
        case addFilter

        fileprivate var defaultVisibility: Visibility {
            switch self {
            case .reactionsPanel, .viewsPanel, .addFilter:
                return .shown
            case .hideMessage:
                return .hidden
            case .senderSearch, .messageDetails:
                return .extended
            }
        }

        fileprivate var storageKey: String {
            "gergram.chat.messageContextMenu.\(rawValue)"
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func visibility(for action: Action) -> Visibility {
        let stored = defaults.string(forKey: action.storageKey)
        return stored.flatMap(Visibility.init(rawValue:)) ?? action.defaultVisibility
    }

    public func setVisibility(_ visibility: Visibility, for action: Action) {
        defaults.set(visibility.rawValue, forKey: action.storageKey)
    }

    public func resetVisibility() {
        for action in Action.allCases {
            defaults.removeObject(forKey: action.storageKey)
        }
    }

    public func isVisible(_ action: Action, extendedMenu: Bool) -> Bool {
        switch visibility(for: action) {
        case .shown:
            return true
        case .hidden:
            return false
        case .extended:
            return extendedMenu
        }
    }
}
