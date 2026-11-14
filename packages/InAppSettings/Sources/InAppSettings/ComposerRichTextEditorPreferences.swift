import Foundation
import SwiftSignalKit

public final class ComposerRichTextEditorPreferences {
    public static let shared = ComposerRichTextEditorPreferences(defaults: .standard)

    private static let key = "gergram.composer.hidesRichTextEditorShortcut"
    private let defaults: UserDefaults
    private let hidden: ValuePromise<Bool>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.hidden = ValuePromise(defaults.bool(forKey: Self.key), ignoreRepeated: true)
    }

    public var hidesShortcut: Bool {
        defaults.bool(forKey: Self.key)
    }

    public var signal: Signal<Bool, NoError> {
        hidden.get()
    }

    public func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.key)
        self.hidden.set(hidden)
    }
}
