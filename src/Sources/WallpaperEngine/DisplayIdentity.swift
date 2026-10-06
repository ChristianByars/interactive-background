import AppKit
import WallpaperCore

extension NSScreen {
    /// The raw CoreGraphics display id. (`NSScreen.CGDirectDisplayID` is macOS 26+, so read the device description.)
    public var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stable across reconnects and reboots, unlike `CGDirectDisplayID`: the display's UUID string.
    public var stableID: DisplayID? {
        displayID.flatMap(NSScreen.stableID(for:))
    }

    public static func stableID(for displayID: CGDirectDisplayID) -> DisplayID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return nil }
        return string as String
    }

    public static func mainDisplayStableID() -> DisplayID? {
        stableID(for: CGMainDisplayID())
    }
}
