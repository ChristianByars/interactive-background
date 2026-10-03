import AppKit

// One borderless window per display, sitting at the desktop layer
// (above the wallpaper image, below Finder icons) hosting injected content.
public final class WallpaperWindow: NSWindow {
    public init(screen: NSScreen, contentView: NSView) {
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

        contentView.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView.autoresizingMask = [.width, .height]
        self.contentView = contentView
    }

    // A wallpaper must never take focus.
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
