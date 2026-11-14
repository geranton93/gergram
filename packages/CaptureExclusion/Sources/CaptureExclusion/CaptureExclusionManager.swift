import Foundation
import AppKit
import ObjcUtils

public final class CaptureExclusionManager {
    private static var windowRegions: [ObjectIdentifier: WindowRegions] = [:]
    private let owner = UUID()

    public init() {
    }

    public struct Token: Hashable {
        public let id: UUID
        public init(id: UUID) {
            self.id = id
        }
    }

    private enum ExclusionSource {
        case fullWindow
        case view(WeakViewRef)
    }

    private struct ExclusionEntry {
        public let window: NSWindow
        public let source: ExclusionSource
    }

    private struct WindowRegions {
        let window: WeakWindowRef
        var regions: [UUID: CGRect]
    }

    private var entries: [Token: ExclusionEntry] = [:]
    private var windowTokens: [ObjectIdentifier: Set<Token>] = [:]
    private var trackedWindows: [ObjectIdentifier: WeakWindowRef] = [:]
    private var observations: [Token: [NSObjectProtocol]] = [:]

    public func addExclusion(for window: NSWindow) -> Token {
        let token = Token(id: UUID())
        let entry = ExclusionEntry(window: window, source: .fullWindow)
        insertEntry(token, entry: entry)
        reapply(for: window)
        return token
    }

    public func addExclusion(for window: NSWindow, view: NSView) -> Token {
        let token = Token(id: UUID())
        let entry = ExclusionEntry(window: window, source: .view(WeakViewRef(view)))
        insertEntry(token, entry: entry)

        var observers: [NSObjectProtocol] = []
        let reapplyBlock: (Notification) -> Void = { [weak self, weak window] _ in
            guard let window = window else { return }
            self?.reapply(for: window)
        }

        view.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: view,
            queue: .main,
            using: reapplyBlock
        ))

        if let scrollView = view.enclosingScrollView {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main,
                using: reapplyBlock
            ))
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main,
                using: reapplyBlock
            ))
        }

        if let superview = view.superview {
            superview.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: superview,
                queue: .main,
                using: reapplyBlock
            ))
        }

        observations[token] = observers
        reapply(for: window)
        return token
    }

    public func forceReapply(for window: NSWindow) {
        DispatchQueue.main.async {
            self.reapply(for: window)
        }
    }

    public func removeExclusion(_ token: Token, for window: NSWindow) {
        guard let entry = entries[token], entry.window === window else { return }
        entries.removeValue(forKey: token)
        removeObservers(for: token)

        let key = ObjectIdentifier(window)
        windowTokens[key]?.remove(token)
        if windowTokens[key]?.isEmpty == true {
            windowTokens.removeValue(forKey: key)
            trackedWindows.removeValue(forKey: key)
        }
        reapply(for: window)
    }

    public func cleanup() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.cleanup() }
            return
        }
        for (_, weakRef) in trackedWindows {
            if let window = weakRef.window {
                Self.applyRegion(nil, for: window, owner: owner)
            }
        }
        for token in observations.keys {
            removeObservers(for: token)
        }
        entries.removeAll()
        windowTokens.removeAll()
        trackedWindows.removeAll()
        observations.removeAll()
    }

    private func insertEntry(_ token: Token, entry: ExclusionEntry) {
        entries[token] = entry
        let key = ObjectIdentifier(entry.window)
        if windowTokens[key] == nil {
            windowTokens[key] = []
            trackedWindows[key] = WeakWindowRef(entry.window)
        }
        windowTokens[key]!.insert(token)
    }

    private func reapply(for window: NSWindow) {
        let key = ObjectIdentifier(window)

        var combined: CGRect?
        for token in windowTokens[key] ?? [] {
            guard let entry = entries[token] else { continue }
            let rect: CGRect
            switch entry.source {
            case .fullWindow:
                rect = CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)
            case .view(let weakView):
                guard let view = weakView.view, view.window === window else { continue }

                guard let superview = view.superview else { continue }
                let windowRect = superview.convert(view.frame, to: nil)
                if windowRect.isEmpty { continue }
                rect = CGRect(
                    x: windowRect.origin.x,
                    y: window.frame.height - windowRect.maxY,
                    width: windowRect.width,
                    height: windowRect.height
                )
            }
            if let existing = combined {
                combined = existing.union(rect)
            } else {
                combined = rect
            }
        }

        Self.applyRegion(combined, for: window, owner: owner)
    }

    private static func applyRegion(_ region: CGRect?, for window: NSWindow, owner: UUID) {
        let key = ObjectIdentifier(window)
        var state = windowRegions[key]
        if state?.window.window !== window {
            state = nil
        }
        if let region = region {
            if state == nil {
                state = WindowRegions(window: WeakWindowRef(window), regions: [:])
            }
            state?.regions[owner] = region
        } else {
            guard state?.regions.removeValue(forKey: owner) != nil else { return }
        }
        if let state = state, let first = state.regions.values.first {
            windowRegions[key] = state
            let combined = state.regions.values.reduce(first) { $0.union($1) }
            setWindowCaptureExclusion(window, combined, true)
        } else {
            windowRegions.removeValue(forKey: key)
            setWindowCaptureExclusion(window, .zero, false)
        }
    }

    private func removeObservers(for token: Token) {
        if let tokenObservers = observations.removeValue(forKey: token) {
            for observer in tokenObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

private final class WeakWindowRef {
    public weak var window: NSWindow?
    public init(_ window: NSWindow) { self.window = window }
}

private final class WeakViewRef {
    public weak var view: NSView?
    public init(_ view: NSView) { self.view = view }
}
