import AppKit
import WallpaperCore

/// Something that draws a wallpaper into a view hosted by a `WallpaperWindow`.
@MainActor
public protocol WallpaperRenderer: AnyObject {
    var view: NSView { get }
    func setPaused(_ paused: Bool)
    func tearDown()
}

/// What a display should show. A refresh rebuilds a display only when `itemID` or
/// `contentURL` changes; a video whose settings alone changed is updated in place.
public enum RenderSpec: Equatable {
    case web(itemID: String, indexURL: URL)
    case video(itemID: String, fileURL: URL, settings: VideoSettings)

    public var itemID: String {
        switch self {
        case .web(let itemID, _): return itemID
        case .video(let itemID, _, _): return itemID
        }
    }

    public var contentURL: URL {
        switch self {
        case .web(_, let indexURL): return indexURL
        case .video(_, let fileURL, _): return fileURL
        }
    }
}
