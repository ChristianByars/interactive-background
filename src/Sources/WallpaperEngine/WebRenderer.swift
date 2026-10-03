import AppKit
import WebKit

/// Renders an HTML/WebGL wallpaper package in a WKWebView.
/// Pausing overlays a snapshot and hides the web view (hiding suspends requestAnimationFrame).
@MainActor
public final class WebRenderer: NSObject, WallpaperRenderer, WKNavigationDelegate {
    private let container = HostView()
    private let webView: WKWebView
    private let overlay = NSImageView()
    /// What the engine last asked for. A pause requested before the page has loaded and the view
    /// is in a window is only recorded here; it is applied once both are true.
    private var wantsPaused = false
    /// Whether the snapshot overlay is actually showing.
    private var pauseApplied = false
    private var pageLoaded = false
    /// Bumped on every pause-state change so a late or superseded snapshot is dropped.
    private var generation = 0
    private let itemID: String
    /// Lets the first frame render before snapshotting.
    private static let settleDelay: TimeInterval = 0.5

    /// Called when the page fails to load.
    public var onLoadFailed: (() -> Void)?

    public var view: NSView { container }

    public init(itemID: String, indexURL: URL) {
        self.itemID = itemID
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.onMovedToWindow = { [weak self] in self?.attemptPause() }

        for sub in [webView, overlay] {
            sub.frame = container.bounds
            sub.autoresizingMask = [.width, .height]
            container.addSubview(sub)
        }
        overlay.imageScaling = .scaleAxesIndependently
        overlay.isHidden = true
        webView.navigationDelegate = self

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        Log.playback.info("web renderer loading \(itemID, privacy: .public)")
    }

    public func setPaused(_ paused: Bool) {
        guard paused != wantsPaused else { return }
        wantsPaused = paused
        generation += 1  // cancels any pending or in-flight snapshot
        if paused {
            attemptPause()
        } else {
            pauseApplied = false
            webView.isHidden = false
            overlay.isHidden = true
            overlay.image = nil
            Log.pause.info("web \(self.itemID, privacy: .public) resumed")
        }
    }

    /// Applies a wanted pause once the page is loaded and the view is in a window.
    private func attemptPause() {
        guard wantsPaused, !pauseApplied, pageLoaded, container.window != nil else { return }
        generation += 1
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            self?.takePauseSnapshot(expected: expected)
        }
    }

    private func takePauseSnapshot(expected: Int) {
        guard wantsPaused, generation == expected else { return }
        let id = itemID
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            MainActor.assumeIsolated {
                guard let self, self.wantsPaused, self.generation == expected else { return }
                guard let image, image.size.width > 0, image.size.height > 0 else {
                    // Keep the live view showing rather than hide it behind nothing.
                    Log.pause.notice("snapshot failed for \(id, privacy: .public): \(error?.localizedDescription ?? "nil or empty image", privacy: .public)")
                    return
                }
                self.overlay.image = image
                self.overlay.isHidden = false
                self.webView.isHidden = true
                self.pauseApplied = true
                Log.pause.info("web \(id, privacy: .public) paused with snapshot")
            }
        }
    }

    public func tearDown() {
        generation += 1
        wantsPaused = false
        container.onMovedToWindow = nil
        onLoadFailed = nil
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        overlay.removeFromSuperview()
    }

    // MARK: WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.playback.info("web \(self.itemID, privacy: .public) loaded")
        pageLoaded = true
        attemptPause()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    private func loadFailed(_ error: Error) {
        Log.playback.error("web \(self.itemID, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
        onLoadFailed?()
    }
}

/// Container that reports when it is placed into a window.
private final class HostView: NSView {
    var onMovedToWindow: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMovedToWindow?() }
    }
}
