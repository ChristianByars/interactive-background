import AppKit
import WallpaperCore

public struct DisplayInfo: Equatable, Sendable {
    public var id: DisplayID
    public var name: String
    public var isMain: Bool

    public init(id: DisplayID, name: String, isMain: Bool) {
        self.id = id
        self.name = name
        self.isMain = isMain
    }
}

/// Facade the app talks to: owns the windows and one renderer per display.
@MainActor
public final class WallpaperEngine {
    private struct Slot {
        var spec: RenderSpec
        var renderer: WallpaperRenderer
    }

    private let displayManager = DisplayManager()
    private let pool = VideoPlayerPool()
    private var slots: [DisplayID: Slot] = [:]
    private var resolve: ((DisplayID) -> RenderSpec)?
    private var manualPause = false
    private let monitor = SystemMonitor()
    private let poller = CoveragePoller()
    /// Window occlusion per display (unknown = not occluded) and the latest polled coverage.
    private var occluded: [DisplayID: Bool] = [:]
    private var polledCovered: [DisplayID: Bool] = [:]
    /// Last pause state applied per display, so transitions are logged once.
    private var pausedState: [DisplayID: Bool] = [:]

    public var onDisplaysChanged: (([DisplayInfo]) -> Void)?
    /// Called with the item id whose content failed to play/load.
    public var onPlaybackFailed: ((String) -> Void)?

    public init() {
        pool.onFailure = { [weak self] itemID in self?.reportFailure(itemID) }
        monitor.onChange = { [weak self] _ in self?.applyPauseState() }
        poller.targets = { [weak self] in self?.pollTargets() ?? [:] }
        poller.onResult = { [weak self] result in
            guard let self, result != self.polledCovered else { return }
            self.polledCovered = result
            self.applyPauseState()
        }
    }

    public func start(resolve: @escaping (DisplayID) -> RenderSpec) {
        self.resolve = resolve
        displayManager.contentProvider = { [weak self] id in
            guard let self, let resolve = self.resolve else { return DisplayManager.blackView() }
            return self.install(resolve(id), for: id)
        }
        displayManager.onRemoved = { [weak self] id in
            guard let self else { return }
            self.slots.removeValue(forKey: id)?.renderer.tearDown()
            self.occluded[id] = nil
            self.polledCovered[id] = nil
            self.pausedState[id] = nil
        }
        displayManager.onOcclusionChanged = { [weak self] id, isOccluded in
            guard let self, self.occluded[id] != isOccluded else { return }
            self.occluded[id] = isOccluded
            Log.pause.info("display \(id, privacy: .public) occluded \(isOccluded)")
            self.applyPauseState()
            // Don't wait up to 2 s for fresh coverage when a display becomes visible again.
            if !isOccluded { self.poller.pollNow() }
        }
        displayManager.onSynced = { [weak self] diff in
            guard let self else { return }
            // Any change matters: a new primary display moves frame origins, so it shows up as `resized`.
            if !diff.added.isEmpty || !diff.removed.isEmpty || !diff.resized.isEmpty {
                self.notifyDisplaysChanged()
            }
            self.applyPauseState()
        }
        monitor.start()
        displayManager.sync(screens: NSScreen.screens)
        displayManager.startObserving()
        applyPauseState()
        notifyDisplaysChanged()
    }

    /// Re-resolve every display; rebuild only displays whose item or file changed.
    /// Settings-only changes are applied live.
    public func refresh() {
        guard let resolve else { return }
        for id in displayManager.displayIDs {
            let spec = resolve(id)
            if let current = slots[id]?.spec,
               current.itemID == spec.itemID, current.contentURL == spec.contentURL {
                if current != spec, case .video(let itemID, _, let settings) = spec {
                    applySettings(itemID: itemID, settings)
                }
                continue
            }
            slots.removeValue(forKey: id)?.renderer.tearDown()
            let view = install(spec, for: id)
            displayManager.setContent(view, for: id)
            Log.playback.notice("display \(id, privacy: .public) now shows \(spec.itemID, privacy: .public)")
        }
        applyPauseState()
    }

    /// Applies speed/audio/trim to the item's shared player and fit to its live layers, without a rebuild.
    public func applySettings(itemID: String, _ settings: VideoSettings) {
        pool.apply(itemID: itemID, settings: settings)
        for (id, slot) in slots {
            guard case .video(let slotItemID, let fileURL, _) = slot.spec, slotItemID == itemID else { continue }
            slots[id]?.spec = .video(itemID: itemID, fileURL: fileURL, settings: settings)
            (slot.renderer as? VideoRenderer)?.setFit(settings.fit)
        }
    }

    public func setManualPause(_ paused: Bool) {
        manualPause = paused
        applyPauseState()
    }

    // MARK: Private

    private func currentPolicy() -> PausePolicy {
        var covered: [DisplayID: Bool] = [:]
        for id in Set(slots.keys).union(occluded.keys).union(polledCovered.keys) {
            covered[id] = occluded[id] == true || polledCovered[id] == true
        }
        return PausePolicy(manualPause: manualPause, systemInactive: monitor.isInactive, covered: covered)
    }

    /// The single place pause is computed: manual || system inactive || covered, per display.
    /// Re-run on every input change (manual, system, occlusion, poll, display changes, new slots).
    private func applyPauseState() {
        // First, so a poller that just started has already reported (its immediate poll re-enters
        // here) and a resume never flashes unpaused before coverage is known.
        updatePoller()
        let policy = currentPolicy()
        for (id, slot) in slots {
            let paused = policy.isPaused(id)
            record(paused, for: id, policy: policy)
            slot.renderer.setPaused(paused)
        }
    }

    /// Logs a display's pause state only when it changes (a display that starts unpaused is silent).
    private func record(_ paused: Bool, for id: DisplayID, policy: PausePolicy) {
        guard (pausedState[id] ?? false) != paused else { return }
        pausedState[id] = paused
        let reason = "manual \(policy.manualPause), system \(policy.systemInactive), covered \(policy.covered[id] ?? false)"
        Log.pause.notice("display \(id, privacy: .public) \(paused ? "paused" : "resumed", privacy: .public) (\(reason, privacy: .public))")
    }

    /// Poll for covering windows only while some display could be playing; clear stale results when idle.
    private func updatePoller() {
        if !slots.isEmpty && !manualPause && !monitor.isInactive {
            poller.start()
        } else {
            poller.stop()
            polledCovered.removeAll()
        }
    }

    /// Displays that still need polling (not occluded, not otherwise paused), with their
    /// usable area (menu bar and Dock excluded) in CG top-left coordinates.
    private func pollTargets() -> [DisplayID: CGRect] {
        guard !manualPause, !monitor.isInactive, let primary = NSScreen.screens.first else { return [:] }
        var targets: [DisplayID: CGRect] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.stableID, slots[id] != nil, occluded[id] != true else { continue }
            targets[id] = CoveragePoller.cgRect(fromAppKit: screen.visibleFrame, primaryHeight: primary.frame.height)
        }
        return targets
    }

    /// Builds the renderer for `spec`, records it for the display, and returns its view.
    /// The renderer is created already in the display's current pause state.
    private func install(_ spec: RenderSpec, for id: DisplayID) -> NSView {
        let policy = currentPolicy()
        let paused = policy.isPaused(id)
        let renderer = makeRenderer(for: spec, display: id, paused: paused)
        slots[id] = Slot(spec: spec, renderer: renderer)
        record(paused, for: id, policy: policy)
        renderer.setPaused(paused)
        return renderer.view
    }

    private func makeRenderer(for spec: RenderSpec, display: DisplayID, paused: Bool) -> WallpaperRenderer {
        switch spec {
        case .web(let itemID, let indexURL):
            let renderer = WebRenderer(itemID: itemID, indexURL: indexURL)
            renderer.onLoadFailed = { [weak self] in self?.reportFailure(itemID) }
            return renderer
        case .video(let itemID, let fileURL, let settings):
            return VideoRenderer(itemID: itemID, fileURL: fileURL, settings: settings, displayID: display, pool: pool, paused: paused)
        }
    }

    /// The app reacts by refreshing, which tears renderers down. Hop to the next main-actor turn
    /// so that never happens re-entrantly inside the renderer's own AVFoundation/WebKit callback.
    private func reportFailure(_ itemID: String) {
        Task { @MainActor [weak self] in self?.onPlaybackFailed?(itemID) }
    }

    private func notifyDisplaysChanged() {
        let main = NSScreen.mainDisplayStableID()  // recomputed every time; the primary can change
        let infos: [DisplayInfo] = NSScreen.screens.compactMap { screen in
            guard let id = screen.stableID, displayManager.entries[id] != nil else { return nil }
            return DisplayInfo(id: id, name: screen.localizedName, isMain: id == main)
        }
        onDisplaysChanged?(infos)
    }
}
