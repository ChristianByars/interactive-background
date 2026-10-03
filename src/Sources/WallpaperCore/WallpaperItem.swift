import Foundation

public enum WallpaperSource: Codable, Equatable, Sendable {
    case video(path: String)
    case web(folder: String)
}

public struct WallpaperItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var source: WallpaperSource
    public var settings: VideoSettings?

    public init(id: String, name: String, source: WallpaperSource, settings: VideoSettings? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.settings = settings
    }

    public static let auroraID = "builtin.aurora"
    public static let aurora = WallpaperItem(
        id: auroraID, name: "Aurora", source: .web(folder: "aurora"), settings: nil)

    public var isBuiltin: Bool { id.hasPrefix("builtin.") }
}
