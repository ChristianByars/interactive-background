import AppKit
import WebKit

// One borderless window per display, sitting at the desktop layer
// (above the wallpaper image, below Finder icons) and hosting a web view.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, pageURL: URL) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        // The key trick: desktop window level.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        // Show on every Space, don't slide during Space switches, stay out of Cmd-` cycling.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Let clicks fall through to Finder / desktop icons.
        ignoresMouseEvents = true

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)

        let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size),
                            configuration: WKWebViewConfiguration())
        web.autoresizingMask = [.width, .height]
        contentView = web
        // Read access to the whole wallpaper folder so a package can load its own assets.
        web.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    // A wallpaper must never take focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [WallpaperWindow] = []
    private let pageURL: URL

    init(pageURL: URL) {
        self.pageURL = pageURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildWindows()
        // Displays plugged in/out or rearranged: rebuild one window per screen.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0, pageURL: pageURL) }
        windows.forEach { $0.orderFrontRegardless() }
    }
}

// Usage: swift run WallpaperSpike [path/to/index.html]
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../wallpapers/aurora/index.html"
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pageURL = URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL

guard FileManager.default.fileExists(atPath: pageURL.path) else {
    print("Wallpaper page not found: \(pageURL.path)")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar takeover
let delegate = AppDelegate(pageURL: pageURL)
app.delegate = delegate // NSApplication holds this weakly; the top-level `delegate` keeps it alive
app.run()
