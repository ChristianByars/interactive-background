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
    private var slots: [DisplayID: Slot] = [:]
    private var resolve: ((DisplayID) -> RenderSpec)?
    private var manualPause = false

    public var onDisplaysChanged: (([DisplayInfo]) -> Void)?
    /// Called with the item id whose content failed to play/load.
    public var onPlaybackFailed: ((String) -> Void)?

    public init() {}

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

    /// Re-resolve every display; rebuild only displays whose item changed.
    public func refresh() {
        guard let resolve else { return }
        for id in displayManager.displayIDs {
            let spec = resolve(id)
            guard slots[id]?.spec.itemID != spec.itemID else { continue }
            slots.removeValue(forKey: id)?.renderer.tearDown()
            let view = install(spec, for: id)
            displayManager.setContent(view, for: id)
            Log.playback.notice("display \(id, privacy: .public) now shows \(spec.itemID, privacy: .public)")
        }
        applyPauseState()
    }

    /// No-op until Task 9 (video settings).
    public func applySettings(itemID: String, _ settings: VideoSettings) {
        // TODO(Task 9): forward to the video renderer / player pool.
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
        let renderer = makeRenderer(for: spec)
        slots[id] = Slot(spec: spec, renderer: renderer)
        renderer.setPaused(manualPause)
        return renderer.view
    }

    private func makeRenderer(for spec: RenderSpec) -> WallpaperRenderer {
        switch spec {
        case .web(let itemID, let indexURL):
            let renderer = WebRenderer(itemID: itemID, indexURL: indexURL)
            renderer.onLoadFailed = { [weak self] in self?.onPlaybackFailed?(itemID) }
            return renderer
        case .video:
            // TODO(Task 9): replace with VideoRenderer. Until then show solid black.
            return BlackRenderer()
        }
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

/// Placeholder renderer for video specs until Task 9.
@MainActor
final class BlackRenderer: WallpaperRenderer {
    let view: NSView = DisplayManager.blackView()
    func setPaused(_ paused: Bool) {}
    func tearDown() {}
}
