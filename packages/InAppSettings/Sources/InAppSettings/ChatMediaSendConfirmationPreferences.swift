import Foundation
import SwiftSignalKit

public struct ChatMediaSendConfirmationOptions: Equatable {
    public let stickers: Bool
    public let gifs: Bool

    fileprivate init(defaults: UserDefaults) {
        stickers = defaults.bool(forKey: ChatMediaSendConfirmationPreferences.Kind.sticker.key)
        gifs = defaults.bool(forKey: ChatMediaSendConfirmationPreferences.Kind.gif.key)
    }
}

public final class ChatMediaSendConfirmationPreferences {
    public enum Kind {
        case sticker
        case gif

        fileprivate var key: String {
            switch self {
            case .sticker: return "Gergram.Chat.ConfirmStickerSends"
            case .gif: return "Gergram.Chat.ConfirmGifSends"
            }
        }
    }

    public static let shared = ChatMediaSendConfirmationPreferences(defaults: .standard)

    private let defaults: UserDefaults
    private let options: ValuePromise<ChatMediaSendConfirmationOptions>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.options = ValuePromise(ChatMediaSendConfirmationOptions(defaults: defaults), ignoreRepeated: true)
    }

    public var signal: Signal<ChatMediaSendConfirmationOptions, NoError> {
        options.get()
    }

    public func isEnabled(for kind: Kind) -> Bool {
        defaults.bool(forKey: kind.key)
    }

    public func set(_ enabled: Bool, for kind: Kind) {
        defaults.set(enabled, forKey: kind.key)
        options.set(ChatMediaSendConfirmationOptions(defaults: defaults))
    }
}
