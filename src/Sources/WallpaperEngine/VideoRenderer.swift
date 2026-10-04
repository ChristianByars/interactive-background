import AppKit
import AVFoundation
import WallpaperCore

/// Shows a pooled video player for one display. Displays showing the same item share one
/// `AVQueuePlayer` (each with its own `AVPlayerLayer`); pause and teardown go through the pool.
@MainActor
final class VideoRenderer: WallpaperRenderer {
    private let playerView = PlayerView()
    private let pool: VideoPlayerPool
    private let itemID: String
    private let displayID: DisplayID
    private var tornDown = false

    var view: NSView { playerView }

    init(itemID: String, fileURL: URL, settings: VideoSettings, displayID: DisplayID, pool: VideoPlayerPool,
         paused: Bool = false) {
        self.itemID = itemID
        self.displayID = displayID
        self.pool = pool
        playerView.playerLayer.player = pool.acquire(
            itemID: itemID, fileURL: fileURL, settings: settings, displayID: displayID, paused: paused)
        setFit(settings.fit)
        Log.playback.info("video renderer for \(itemID, privacy: .public) on display \(displayID, privacy: .public)")
    }

    func setFit(_ fit: FitMode) {
        playerView.playerLayer.videoGravity = Self.gravity(for: fit)
    }

    func setPaused(_ paused: Bool) {
        guard !tornDown else { return }
        pool.setPaused(itemID: itemID, displayID: displayID, paused: paused)
    }

    func tearDown() {
        guard !tornDown else { return }
        tornDown = true
        playerView.playerLayer.player = nil
        pool.release(itemID: itemID, displayID: displayID)
    }

    static func gravity(for fit: FitMode) -> AVLayerVideoGravity {
        switch fit {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}

/// Layer-backed view whose backing layer is the `AVPlayerLayer`, so AppKit keeps it sized.
private final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { playerLayer }
}
