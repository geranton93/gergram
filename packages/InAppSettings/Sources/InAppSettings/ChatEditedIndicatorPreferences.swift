import Foundation
import SwiftSignalKit

public enum ChatEditedIndicatorStyle: String, CaseIterable {
    case text
    case icon
    case hidden
}

public final class ChatEditedIndicatorPreferences {
    public static let shared = ChatEditedIndicatorPreferences(defaults: .standard)

    private static let key = "Gergram.Chat.EditedIndicatorStyle"
    private let defaults: UserDefaults
    private let style: ValuePromise<ChatEditedIndicatorStyle>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let storedStyle = defaults.string(forKey: Self.key).flatMap(ChatEditedIndicatorStyle.init(rawValue:))
        self.style = ValuePromise(storedStyle ?? .text, ignoreRepeated: true)
    }

    public var signal: Signal<ChatEditedIndicatorStyle, NoError> {
        style.get()
    }

    public func set(_ value: ChatEditedIndicatorStyle) {
        defaults.set(value.rawValue, forKey: Self.key)
        style.set(value)
    }
}
