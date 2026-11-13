import Foundation
import SwiftSignalKit

public enum ChatMessageWidth: String, CaseIterable {
    case compact
    case standard
    case wide

    public var maximumBubbleWidth: CGFloat {
        switch self {
        case .compact: return 360
        case .standard: return 450
        case .wide: return 600
        }
    }
}

public final class ChatMessageWidthPreferences {
    public static let shared = ChatMessageWidthPreferences(defaults: .standard)

    private static let key = "Gergram.Chat.MessageWidth"
    private let defaults: UserDefaults
    private let value: ValuePromise<ChatMessageWidth>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.value = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    public var width: ChatMessageWidth {
        Self.read(from: defaults)
    }

    public var signal: Signal<ChatMessageWidth, NoError> {
        value.get()
    }

    public func set(_ width: ChatMessageWidth) {
        defaults.set(width.rawValue, forKey: Self.key)
        value.set(width)
    }

    private static func read(from defaults: UserDefaults) -> ChatMessageWidth {
        defaults.string(forKey: Self.key).flatMap(ChatMessageWidth.init(rawValue:)) ?? .standard
    }
}
