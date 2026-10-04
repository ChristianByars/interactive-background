import AppKit
import WallpaperCore

/// Tracks screen sleep, session switch, lock and screensaver state and reports whether the
/// system is inactive (nothing worth rendering). Flag logic lives in Core's `SystemActivity`.
@MainActor
final class SystemMonitor {
    private(set) var activity = SystemActivity()
    var isInactive: Bool { activity.isInactive }

    /// Called with the new `isInactive` whenever it changes.
    var onChange: ((Bool) -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.screensDidSleepNotification, .screensSlept, "screens slept")
        observe(workspace, NSWorkspace.screensDidWakeNotification, .screensWoke, "screens woke")
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned, "session resigned")
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive, "session became active")
        // These two have no public constants.
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .locked, "screen locked")
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .unlocked, "screen unlocked")
        observe(distributed, Notification.Name("com.apple.screensaver.didstart"), .screensaverStarted, "screensaver started")
        observe(distributed, Notification.Name("com.apple.screensaver.didstop"), .screensaverStopped, "screensaver stopped")
        Log.pause.notice("system monitor started")
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ event: SystemActivity.Event, _ label: String) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(event, label) }
        }
        observers.append((center, token))
    }

    private func handle(_ event: SystemActivity.Event, _ label: String) {
        let before = isInactive
        activity.apply(event)
        Log.pause.notice("system event: \(label, privacy: .public) -> inactive \(self.isInactive)")
        if isInactive != before { onChange?(isInactive) }
    }
}
