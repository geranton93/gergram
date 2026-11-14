import Foundation
import SwiftSignalKit

public final class MessageBubbleRadiusPreferences {
    public static let defaultRadius = 16
    public static let allowedRadii = 0 ... defaultRadius
    public static let shared = MessageBubbleRadiusPreferences(defaults: .standard)

    private static let key = "Gergram.Chat.MessageBubbleRadius"
    private let defaults: UserDefaults
    private let value: ValuePromise<Int>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.value = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    public var radius: Int {
        Self.read(from: defaults)
    }

    public var signal: Signal<Int, NoError> {
        value.get()
    }

    public func setRadius(_ radius: Int) {
        guard Self.allowedRadii.contains(radius) else {
            return
        }
        defaults.set(radius, forKey: Self.key)
        value.set(radius)
    }

    private static func read(from defaults: UserDefaults) -> Int {
        guard let radius = defaults.object(forKey: Self.key) as? Int, allowedRadii.contains(radius) else {
            return defaultRadius
        }
        return radius
    }
}
