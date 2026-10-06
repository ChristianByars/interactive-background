import CoreGraphics
import Foundation

public enum Coverage {
    public struct WindowInfo: Equatable, Sendable {
        public var frame: CGRect
        public var layer: Int
        public var ownerPID: Int32
        public var alpha: Double

        public init(frame: CGRect, layer: Int, ownerPID: Int32, alpha: Double) {
            self.frame = frame
            self.layer = layer
            self.ownerPID = ownerPID
            self.alpha = alpha
        }
    }

    /// `displayRect` is the display's usable area (screen minus menu bar and Dock) in the
    /// same coordinate space as the window frames. Covered when a normal-layer, opaque
    /// window of another process contains that rect shrunk by 4 pt.
    public static func isCovered(displayRect: CGRect, windows: [WindowInfo], ownPID: Int32) -> Bool {
        let target = displayRect.insetBy(dx: 4, dy: 4)
        return windows.contains {
            $0.layer == 0 && $0.ownerPID != ownPID && $0.alpha >= 0.95 && $0.frame.contains(target)
        }
    }
}
