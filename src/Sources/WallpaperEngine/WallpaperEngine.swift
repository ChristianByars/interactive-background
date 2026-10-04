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

    public var onDisplaysChanged: (([DisplayInfo]) -> Void)?
    /// Called with the item id whose content failed to play/load.
    public var onPlaybackFailed: ((String) -> Void)?

    public init() {
        pool.onFailure = { [weak self] itemID in self?.reportFailure(itemID) }
    }

    public func start(resolve: @escaping (DisplayID) -> RenderSpec) {
        self.resolve = resolve
        displayManager.contentProvider = { [weak self] id in
            guard let self, let resolve = self.resolve else { return DisplayManager.blackView() }
            return self.install(resolve(id), for: id)
        }
        displayManager.onRemoved = { [weak self] id in
            self?.slots.removeValue(forKey: id)?.renderer.tearDown()
        }
        displayManager.onSynced = { [weak self] diff in
            guard let self else { return }
            // Any change matters: a new primary display moves frame origins, so it shows up as `resized`.
            if !diff.added.isEmpty || !diff.removed.isEmpty || !diff.resized.isEmpty {
                self.notifyDisplaysChanged()
            }
        }
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

    /// The single place pause is computed. Task 10 will replace this with
    /// `PausePolicy` (manualPause || systemInactive || covered[display]) per display.
    private func applyPauseState() {
        for (_, slot) in slots {
            slot.renderer.setPaused(manualPause)
        }
    }

    /// Builds the renderer for `spec`, records it for the display, and returns its view.
    private func install(_ spec: RenderSpec, for id: DisplayID) -> NSView {
        let renderer = makeRenderer(for: spec, display: id)
        slots[id] = Slot(spec: spec, renderer: renderer)
        renderer.setPaused(manualPause)
        return renderer.view
    }

    private func makeRenderer(for spec: RenderSpec, display: DisplayID) -> WallpaperRenderer {
        switch spec {
        case .web(let itemID, let indexURL):
            let renderer = WebRenderer(itemID: itemID, indexURL: indexURL)
            renderer.onLoadFailed = { [weak self] in self?.reportFailure(itemID) }
            return renderer
        case .video(let itemID, let fileURL, let settings):
            return VideoRenderer(itemID: itemID, fileURL: fileURL, settings: settings, displayID: display, pool: pool)
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
