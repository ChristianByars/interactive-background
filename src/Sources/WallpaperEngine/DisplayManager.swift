import AppKit
import WallpaperCore

/// One `WallpaperWindow` per screen, keyed by display UUID. Only changed windows are touched.
@MainActor
final class DisplayManager {
    struct Entry {
        let window: WallpaperWindow
        var frame: CGRect
    }

    private(set) var entries: [DisplayID: Entry] = [:]
    private var observer: NSObjectProtocol?

    /// Supplies the content view for a newly added display.
    var contentProvider: ((DisplayID) -> NSView)?
    /// Called after a display's window is closed.
    var onRemoved: ((DisplayID) -> Void)?
    /// Called after a screen-parameters notification has been synced.
    var onSynced: ((DisplayDiff) -> Void)?

    var displayIDs: [DisplayID] { Array(entries.keys) }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let diff = self.sync(screens: NSScreen.screens)
                self.onSynced?(diff)
            }
        }
    }

    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func setContent(_ view: NSView, for id: DisplayID) {
        guard let entry = entries[id] else { return }
        entry.window.replaceContent(view)
    }

    @discardableResult
    func sync(screens: [NSScreen]) -> DisplayDiff {
        var byID: [DisplayID: NSScreen] = [:]
        for screen in screens {
            guard let id = screen.stableID else {
                Log.display.error("screen without a display UUID skipped: \(screen.localizedName, privacy: .public)")
                continue
            }
            byID[id] = screen
        }

        let old = entries.mapValues(\.frame)
        let new = byID.mapValues(\.frame)
        let diff = DisplayDiff.compute(old: old, new: new)

        for id in diff.removed {
            guard let entry = entries.removeValue(forKey: id) else { continue }
            entry.window.orderOut(nil)
            entry.window.close()
            onRemoved?(id)
            Log.display.notice("window removed for display \(id, privacy: .public)")
        }
        for id in diff.added {
            guard let screen = byID[id] else { continue }
            let content = contentProvider?(id) ?? Self.blackView()
            let window = WallpaperWindow(screen: screen, contentView: content)
            window.orderFrontRegardless()
            entries[id] = Entry(window: window, frame: screen.frame)
            Log.display.notice("window created for display \(id, privacy: .public) (\(screen.localizedName, privacy: .public)) frame \(NSStringFromRect(screen.frame), privacy: .public)")
        }
        for id in diff.resized {
            guard let screen = byID[id], var entry = entries[id] else { continue }
            entry.window.setFrame(screen.frame, display: true)
            entry.frame = screen.frame
            entries[id] = entry
            Log.display.notice("window resized for display \(id, privacy: .public) to \(NSStringFromRect(screen.frame), privacy: .public)")
        }
        Log.display.info("sync: \(self.entries.count) window(s), +\(diff.added.count) -\(diff.removed.count) ~\(diff.resized.count)")
        return diff
    }

    func tearDownAll() {
        stopObserving()
        for id in Array(entries.keys) {
            guard let entry = entries.removeValue(forKey: id) else { continue }
            entry.window.orderOut(nil)
            entry.window.close()
            onRemoved?(id)
        }
    }

    static func blackView() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        return v
    }
}
