import Foundation
import SwiftSignalKit

public enum ChatMonospaceFont: String, CaseIterable {
    case system
    case menlo
    case monaco
}

public final class ChatMonospaceFontPreferences {
    public static let shared = ChatMonospaceFontPreferences(defaults: .standard)

    private static let key = "Gergram.Chat.MonospaceFont"
    private let defaults: UserDefaults
    private let value: ValuePromise<ChatMonospaceFont>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.value = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    public var font: ChatMonospaceFont {
        Self.read(from: defaults)
    }

    public var signal: Signal<ChatMonospaceFont, NoError> {
        value.get()
    }

    public func set(_ font: ChatMonospaceFont) {
        defaults.set(font.rawValue, forKey: Self.key)
        value.set(font)
    }

    private static func read(from defaults: UserDefaults) -> ChatMonospaceFont {
        defaults.string(forKey: Self.key).flatMap(ChatMonospaceFont.init(rawValue:)) ?? .system
    }
}
