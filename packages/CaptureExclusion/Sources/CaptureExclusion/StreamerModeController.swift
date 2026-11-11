import AppKit

public final class StreamerModeController {
    public static let shared = StreamerModeController()

    private let preferenceKey = "gergram.streamerMode"
    private let manager = CaptureExclusionManager()
    private var exclusions: [ObjectIdentifier: (number: Int, token: CaptureExclusionManager.Token)] = [:]
    private var observations: [NSObjectProtocol] = []

    private init() {
    }

    public var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    public func restore() {
        if isEnabled {
            startObservingWindows()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            startObservingWindows()
        } else {
            for observer in observations {
                NotificationCenter.default.removeObserver(observer)
            }
            observations.removeAll()
            exclusions.removeAll()
            manager.cleanup()
        }
    }

    private func startObservingWindows() {
        guard observations.isEmpty else { return }
        let center = NotificationCenter.default
        let updates = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didUpdateNotification,
            NSWindow.didResizeNotification
        ]
        for name in updates {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let window = notification.object as? NSWindow else { return }
                self.protect(window, resized: notification.name == NSWindow.didResizeNotification)
            })
        }
        observations.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let window = notification.object as? NSWindow else { return }
            self.unprotect(window)
        })
        for window in NSApplication.shared.windows {
            protect(window)
        }
    }

    private func protect(_ window: NSWindow, resized: Bool = false) {
        guard isEnabled else { return }
        let number = window.windowNumber
        guard window.isVisible, number > 0 else {
            unprotect(window)
            return
        }
        let key = ObjectIdentifier(window)
        if let exclusion = exclusions[key] {
            if resized || exclusion.number != number {
                exclusions[key] = (number, exclusion.token)
                manager.forceReapply(for: window)
            }
        } else {
            exclusions[key] = (number, manager.addExclusion(for: window))
        }
    }

    private func unprotect(_ window: NSWindow) {
        if let exclusion = exclusions.removeValue(forKey: ObjectIdentifier(window)) {
            manager.removeExclusion(exclusion.token, for: window)
        }
    }
}
