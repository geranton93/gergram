import Foundation
import SwiftSignalKit

public final class StreamerModeMenuBarPreferences {
    public enum Action: String, CaseIterable {
        case myProfile, savedMessages, streamerMode

        fileprivate var key: String {
            switch self {
            case .myProfile: return "gergram.menuBar.showsMyProfile"
            case .savedMessages: return "gergram.menuBar.showsSavedMessages"
            case .streamerMode: return "gergram.menuBar.showsStreamerMode"
            }
        }
    }

    public static let shared = StreamerModeMenuBarPreferences(defaults: .standard)
    public static let defaultActions: Set<Action> = [.streamerMode]

    private let defaults: UserDefaults
    private let actions: ValuePromise<Set<Action>>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.actions = ValuePromise(Self.visibleActions(in: defaults), ignoreRepeated: true)
    }

    private static func visibleActions(in defaults: UserDefaults) -> Set<Action> {
        return Set(Action.allCases.filter { defaults.object(forKey: $0.key) as? Bool ?? defaultActions.contains($0) })
    }

    public var actionsSignal: Signal<Set<Action>, NoError> {
        actions.get()
    }

    public func setVisible(_ visible: Bool, for action: Action) {
        defaults.set(visible, forKey: action.key)
        actions.set(Self.visibleActions(in: defaults))
    }

    public func reset() {
        for action in Action.allCases {
            defaults.set(Self.defaultActions.contains(action), forKey: action.key)
        }
        actions.set(Self.defaultActions)
    }

    public var signal: Signal<Bool, NoError> {
        actionsSignal |> map { $0.contains(.streamerMode) } |> distinctUntilChanged
    }

    public func setVisible(_ visible: Bool) {
        setVisible(visible, for: .streamerMode)
    }
}
