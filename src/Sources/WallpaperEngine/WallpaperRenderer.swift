import AppKit
import WallpaperCore

/// Something that draws a wallpaper into a view hosted by a `WallpaperWindow`.
@MainActor
public protocol WallpaperRenderer: AnyObject {
    var view: NSView { get }
    func setPaused(_ paused: Bool)
    func tearDown()
}

/// What a display should show. Equality decides whether a refresh rebuilds a display:
/// the engine compares `itemID` only, so settings changes never rebuild.
public enum RenderSpec: Equatable {
    case web(itemID: String, indexURL: URL)
    case video(itemID: String, fileURL: URL, settings: VideoSettings)

    public var itemID: String {
        switch self {
        case .web(let itemID, _): return itemID
        case .video(let itemID, _, _): return itemID
        }
    }
}
