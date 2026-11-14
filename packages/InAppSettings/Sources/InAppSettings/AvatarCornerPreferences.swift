import Foundation
import SwiftSignalKit

public struct AvatarCornerAppearance: Equatable {
    public let radius: Int
    public let usesSingleRadius: Bool

    public init(radius: Int = AvatarCornerPreferences.defaultRadius, usesSingleRadius: Bool = false) {
        self.radius = AvatarCornerPreferences.allowedRadii.contains(radius) ? radius : AvatarCornerPreferences.defaultRadius
        self.usesSingleRadius = usesSingleRadius
    }

    public func preferredRadius(for size: CGSize, isForum: Bool, explicitRadius: CGFloat?, preservesShape: Bool) -> CGFloat? {
        guard explicitRadius == nil, !preservesShape, !isForum || usesSingleRadius,
              isForum || radius != AvatarCornerPreferences.defaultRadius else { return nil }
        return CGFloat(radius) * min(size.width, size.height) / CGFloat(2 * AvatarCornerPreferences.defaultRadius)
    }
}

public final class AvatarCornerPreferences {
    public static let defaultRadius = 23
    public static let allowedRadii = 0 ... defaultRadius
    public static let shared = AvatarCornerPreferences(defaults: .standard)

    private static let radiusKey = "Gergram.Appearance.AvatarRadius"
    private static let singleRadiusKey = "Gergram.Appearance.SingleAvatarRadius"
    private let defaults: UserDefaults
    private let value: ValuePromise<AvatarCornerAppearance>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.value = ValuePromise(Self.read(defaults), ignoreRepeated: true)
    }

    public var appearance: AvatarCornerAppearance {
        Self.read(defaults)
    }

    public var signal: Signal<AvatarCornerAppearance, NoError> {
        value.get()
    }

    public func setRadius(_ radius: Int) {
        guard Self.allowedRadii.contains(radius) else { return }
        defaults.set(radius, forKey: Self.radiusKey)
        value.set(appearance)
    }

    public func setUsesSingleRadius(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.singleRadiusKey)
        value.set(appearance)
    }

    private static func read(_ defaults: UserDefaults) -> AvatarCornerAppearance {
        AvatarCornerAppearance(
            radius: defaults.object(forKey: radiusKey) as? Int ?? defaultRadius,
            usesSingleRadius: defaults.bool(forKey: singleRadiusKey)
        )
    }
}
