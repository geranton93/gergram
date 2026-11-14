import Foundation
import SwiftSignalKit

public final class ChatReactionVisibilityPreferences {
    public enum ChatKind: String, CaseIterable {
        case privateChat
        case group
        case channel
    }

    public static let shared = ChatReactionVisibilityPreferences(defaults: .standard)

    private static let key = "gergram.chat.hiddenReactionKinds"
    private let defaults: UserDefaults
    private let hiddenKinds: ValuePromise<Set<ChatKind>>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.hiddenKinds = ValuePromise(Self.read(from: defaults), ignoreRepeated: true)
    }

    private static func read(from defaults: UserDefaults) -> Set<ChatKind> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(ChatKind.init(rawValue:)))
    }

    public var signal: Signal<Set<ChatKind>, NoError> {
        hiddenKinds.get()
    }

    public func setHidden(_ hidden: Bool, for kind: ChatKind) {
        var kinds = Self.read(from: defaults)
        if hidden {
            kinds.insert(kind)
        } else {
            kinds.remove(kind)
        }
        setHiddenKinds(kinds)
    }

    public func setHiddenKinds(_ kinds: Set<ChatKind>) {
        defaults.set(kinds.map(\.rawValue).sorted(), forKey: Self.key)
        hiddenKinds.set(kinds)
    }
}
