import Foundation
import SwiftSignalKit

public final class ChatAffordancePreferences {
    public static let shared = ChatAffordancePreferences(defaults: .standard)

    private static let fastShareKey = "Gergram.Chat.HideFastShare"
    private static let greetingStickerKey = "Gergram.Chat.HideGreetingSticker"
    private let defaults: UserDefaults
    private let fastShare: ValuePromise<Bool>
    private let greetingSticker: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.fastShare = ValuePromise(defaults.bool(forKey: Self.fastShareKey), ignoreRepeated: true)
        self.greetingSticker = ValuePromise(defaults.bool(forKey: Self.greetingStickerKey), ignoreRepeated: true)
    }

    public var hidesFastShare: Bool {
        defaults.bool(forKey: Self.fastShareKey)
    }

    public var hidesGreetingSticker: Bool {
        defaults.bool(forKey: Self.greetingStickerKey)
    }

    public var hidesFastShareSignal: Signal<Bool, NoError> {
        fastShare.get()
    }

    public var hidesGreetingStickerSignal: Signal<Bool, NoError> {
        greetingSticker.get()
    }

    public func setHidesFastShare(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.fastShareKey)
        fastShare.set(hidden)
    }

    public func setHidesGreetingSticker(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.greetingStickerKey)
        greetingSticker.set(hidden)
    }
}
