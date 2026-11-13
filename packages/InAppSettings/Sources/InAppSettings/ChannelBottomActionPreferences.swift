import Foundation
import SwiftSignalKit

public enum ChannelBottomAction: String, CaseIterable {
    case native
    case hidden
    case mute
    case discussion
}

public final class ChannelBottomActionPreferences {
    public static let shared = ChannelBottomActionPreferences(defaults: .standard)

    private static let key = "gergram.chat.channelBottomAction"
    private let defaults: UserDefaults
    private let actionValue: ValuePromise<ChannelBottomAction>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.actionValue = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    public var action: ChannelBottomAction {
        Self.read(from: defaults)
    }

    public var signal: Signal<ChannelBottomAction, NoError> {
        actionValue.get()
    }

    public func setAction(_ action: ChannelBottomAction) {
        defaults.set(action.rawValue, forKey: Self.key)
        actionValue.set(action)
    }

    private static func read(from defaults: UserDefaults) -> ChannelBottomAction {
        defaults.string(forKey: Self.key).flatMap(ChannelBottomAction.init(rawValue:)) ?? .native
    }
}
