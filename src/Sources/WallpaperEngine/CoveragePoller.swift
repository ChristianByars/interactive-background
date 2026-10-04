import AppKit
import WallpaperCore

/// Detects a full-screen or maximized window of another app on a display. Occlusion state
/// alone may not report these for a desktop-level window, so the engine also polls the window list.
@MainActor
final class CoveragePoller {
    static let interval: TimeInterval = 2
    /// A usable area smaller than this in either dimension is treated as not covered.
    nonisolated static let minimumSide: CGFloat = 8

    /// Usable areas, in CG top-left coordinates, of the displays that still need polling
    /// (not occluded, not otherwise paused). Evaluated on every poll.
    var targets: (() -> [DisplayID: CGRect])?
    /// Polled result for exactly the displays that were polled.
    var onResult: (([DisplayID: Bool]) -> Void)?

    private var timer: Timer?
    private var ownPID: Int32 { ProcessInfo.processInfo.processIdentifier }
    var isRunning: Bool { timer != nil }

    /// Starts the repeating timer and polls once immediately. No-op if already running.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.pause.notice("coverage poller started")
        pollNow()
    }

    func stop() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        Log.pause.notice("coverage poller stopped")
    }

    func pollNow() {
        guard timer != nil, let targets = targets?() else { return }
        var result: [DisplayID: Bool] = [:]
        let candidates = targets.filter { Self.isUsable($0.value) }
        for id in targets.keys where candidates[id] == nil { result[id] = false }
        if !candidates.isEmpty {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            let windows = Self.windowInfos(from: list as? [[String: Any]] ?? [])
            for (id, rect) in candidates {
                result[id] = Coverage.isCovered(displayRect: rect, windows: windows, ownPID: ownPID)
            }
        }
        onResult?(result)
    }

    // MARK: Pure helpers (tested)

    nonisolated static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// AppKit bottom-left rect (relative to the primary screen's bottom-left origin) -> CG top-left rect.
    nonisolated static func cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryHeight - (rect.origin.y + rect.height),
               width: rect.width, height: rect.height)
    }

    /// Maps `CGWindowListCopyWindowInfo` entries to `Coverage.WindowInfo`; entries missing
    /// a key are skipped.
    nonisolated static func windowInfos(from entries: [[String: Any]]) -> [Coverage.WindowInfo] {
        entries.compactMap { entry in
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            else { return nil }
            return Coverage.WindowInfo(frame: frame, layer: layer, ownerPID: pid, alpha: alpha)
        }
    }
}
