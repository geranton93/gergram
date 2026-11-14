import Foundation
import SwiftSignalKit

public enum ChatEditedIndicatorStyle: String, CaseIterable {
    case text
    case icon
    case hidden
}

public struct ChatEditedIndicatorAppearance: Equatable {
    public let style: ChatEditedIndicatorStyle
    public let customText: String?

    public init(style: ChatEditedIndicatorStyle = .text) {
        self.init(style: style, customText: nil)
    }

    fileprivate init(style: ChatEditedIndicatorStyle, customText: String?) {
        self.style = style
        self.customText = customText.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public final class ChatEditedIndicatorPreferences {
    public static let shared = ChatEditedIndicatorPreferences(defaults: .standard)
    public static let maximumCustomTextLength = ChatIndicatorCustomText.maximumLength
    public static let maximumCustomTextUTF16Length = ChatIndicatorCustomText.maximumUTF16Length

    private static let key = "Gergram.Chat.EditedIndicatorStyle"
    private static let textKey = "Gergram.Chat.EditedIndicatorCustomText"
    private let defaults: UserDefaults
    private let current: ValuePromise<ChatEditedIndicatorAppearance>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.current = ValuePromise(Self.load(from: defaults), ignoreRepeated: true)
    }

    public var appearance: ChatEditedIndicatorAppearance {
        Self.load(from: defaults)
    }

    public var appearanceSignal: Signal<ChatEditedIndicatorAppearance, NoError> {
        current.get()
    }

    public var signal: Signal<ChatEditedIndicatorStyle, NoError> {
        appearanceSignal |> map(\.style) |> distinctUntilChanged
    }

    public func set(_ value: ChatEditedIndicatorStyle) {
        defaults.set(value.rawValue, forKey: Self.key)
        current.set(appearance)
    }

    @discardableResult
    public func setCustomText(_ value: String) -> Bool {
        guard let text = ChatIndicatorCustomText.validated(value) else { return false }
        defaults.set(text, forKey: Self.textKey)
        current.set(appearance)
        return true
    }

    public func reset() {
        defaults.set(ChatEditedIndicatorStyle.text.rawValue, forKey: Self.key)
        defaults.set("", forKey: Self.textKey)
        current.set(.init())
    }

    private static func load(from defaults: UserDefaults) -> ChatEditedIndicatorAppearance {
        let style = defaults.string(forKey: Self.key).flatMap(ChatEditedIndicatorStyle.init(rawValue:)) ?? .text
        let text = defaults.string(forKey: Self.textKey).flatMap(ChatIndicatorCustomText.validated)
        return .init(style: style, customText: text)
    }
}
